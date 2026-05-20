![](https://github.com/jessedrelick/agens/actions/workflows/main.yml/badge.svg)
[![Hexdocs](https://img.shields.io/badge/hex-docs-blue.svg)](https://hexdocs.pm/agens)
[![Hex.pm](https://img.shields.io/hexpm/v/agens.svg)](https://hex.pm/packages/agens)
[![codecov](https://codecov.io/gh/jessedrelick/agens/graph/badge.svg?token=KTJXB4SGCJ)](https://codecov.io/gh/jessedrelick/agens)

__Agens__ is an Elixir application designed to build multi-agent workflows with language models.

Drawing inspiration from popular tools in the Python ecosystem, such as [LangChain](https://www.langchain.com/)/[LangGraph](https://www.langchain.com/langgraph) and [CrewAI](https://www.crewai.com/), __Agens__ showcases Elixir's unique strengths in multi-agent workflows. While the ML/AI landscape is dominated by Python, Elixir's use of the BEAM virtual machine and OTP (Open Telecom Platform), specifically GenServers and Supervisors, makes it particularly well-suited for these tasks. Agens aims to demonstrate how these inherent design features can be leveraged effectively.

> **⚠️ Breaking Changes:** v0.2
>
> Agens has changed significantly since the original 0.1 release (August 2024). The 0.2 line is a substantial redesign:
>
> - The `Agens.Agent` module has been removed. `agent_id` survives as an opaque identifier used by a Serving's `c:Agens.Serving.load_context/2` callback.
> - `Agens.Job.Step` has been replaced by `Agens.Job.Node`. Jobs are now graphs of Nodes, not sequences of Steps.
> - Routing is dynamic and lives on the Serving (via `Agens.Router`), not on static step configuration.
> - Observability moved to the `Agens.Backend` behaviour (default backends emit messages to the caller and write structured logs).
> - Tool calls are configured per-Node via the `:tools` field and executed by the Serving's `c:Agens.Serving.tool_call/3` callback (now modeled after MCP tool calls).

## Installation
Add `agens` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:agens, "~> 0.2.0"}
  ]
end
```

## Usage
A multi-agent workflow with Agens has four moving parts: a **Serving** (the LM interface), a **Router** (routing logic on top of structured outputs), a **Job** (a graph of `Node`s), and optional **Backends** (observability/persistence). Most workflows only need one Serving and one Router.

---
**1. Add the Agens Supervisor to your supervision tree**

```elixir
children = [
  {Agens.Supervisor, name: Agens.Supervisor}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

See `Agens.Supervisor` for more information.

---
**2. Define and start a Serving**

A **Serving** wraps language model inference. Implement the `Agens.Serving` behaviour, `use Agens.Serving`, and call your LM of choice (HTTP API, `Nx.Serving`/`Bumblebee` pipeline, anything else) inside `c:Agens.Serving.handle_message/3`.

```elixir
defmodule MyApp.Serving do
  use Agens.Serving
  use Agens.Router

  alias Agens.{Message, Serving}

  @impl Serving
  def start(state), do: {:ok, state}

  @impl Serving
  def handle_message(_state, %Message{system: system, user: user}, schema) do
    # Call your LM with the prepared system/user prompts + JSON schema, return
    # `{:ok, parsed}` or `{:error, reason}`.
  end

  @impl Serving
  def handle_result({:ok, %{"body" => body} = parsed}, _state, _msg) do
    {:ok, %Serving.Result{body: body, outputs: Map.get(parsed, "outputs", %{})}}
  end

  def handle_result({:error, reason}, _state, _msg), do: {:error, reason}

  # Router callbacks (see step 3)
  @impl Agens.Router
  def outputs(%Message{}), do: []

  @impl Agens.Router
  def resolve(%Message{}, _outputs), do: [:end]
end

{:ok, _pid} =
  Agens.Serving.start(%Agens.Serving.Config{
    name: :my_serving,
    serving: MyApp.Serving
  })
```

See `Agens.Serving` and `examples/servings/` for reference Serving implementations.

---
**3. Define a Router**

A **Router** maps a Serving's structured outputs to a list of routing instructions (`{:route, node_id, count}`, `{:yield, node_id}`, `{:sub, job_id}`, `:end`, `:retry`).

A Router can live in the Serving module itself (the "merged" pattern shown above) or in a dedicated module passed via `use Agens.Serving, router: MyRouter` (the "split" pattern — useful when many Servings share the same routing logic).

```elixir
defmodule MyApp.LinearRouter do
  use Agens.Router

  alias Agens.Message

  @impl Agens.Router
  def outputs(%Message{}), do: []

  @impl Agens.Router
  def resolve(%Message{node_id: "summarize"}, _), do: [{:route, "critique", 1}]
  def resolve(%Message{node_id: "critique"}, _), do: [:end]
end
```

For routing decisions that depend on the LM's structured response, declare an `Agens.Router.Output` schema and use `Agens.Router.Condition` to branch:

```elixir
def outputs(%Message{}) do
  [
    %Output{key: "viable", type: "bool", description: "Is the topic researchable?"},
    %Output{key: "confidence", type: "int", description: "1-10 confidence in the result"}
  ]
end

def resolve(_msg, outputs) do
  cond do
    Condition.check(%Condition{key: "viable", op: "eq", value: "false"}, outputs) -> [:end]
    Condition.check(%Condition{key: "confidence", op: "lt", value: "7"}, outputs) -> [:retry]
    true -> [{:route, "writer", 1}]
  end
end
```

See `Agens.Router`, `Agens.Router.Output`, `Agens.Router.Condition`, and `examples/router/` for more.

---
**4. Define and run a Job**

A **Job** is a graph of `Agens.Job.Node`s with a designated `:starting_node_id`. Each Node declares a Serving and, optionally, an `agent_id`, `objective`, `tools`, `resources`, or a `sub` Job. Routing between Nodes is decided at runtime by the Serving's Router — there is no static `next` field on a Node.

```elixir
config = %Agens.Job.Config{
  id: "summarize_critique",
  description: "Summarize a topic in three sentences, then critique the summary.",
  starting_node_id: "summarize",
  nodes: %{
    "summarize" => %Agens.Job.Node{
      serving: :my_serving,
      agent_id: "summarizer",
      objective: "Write a tight three-sentence summary of the topic."
    },
    "critique" => %Agens.Job.Node{
      serving: :my_serving,
      agent_id: "critic",
      objective: "Identify one weakness or omission in the summary."
    }
  }
}

run_id = Agens.generate_uid()

{:ok, _pid} = Agens.Job.start(config, run_id)
:ok = Agens.Job.run(run_id, "the rise of small open-weight LLMs", [])
```

Jobs are addressed by `run_id` (not name) so the same `Job.Config` can be executed in parallel. See `Agens.Job`, `Agens.Job.Config`, and `Agens.Job.Node`.

---
**5. Observe via Backends (optional)**

The `Agens.Backend` behaviour fans out lifecycle and Node activity to one or more backends. Defaults are configured via the `:backends` application key:

```elixir
config :agens, backends: [Agens.Backend.Emit, Agens.Backend.Log, MyApp.PubSubBackend]
```

The default emit backend sends `{:job_started, _, _}`, `{:node_started, msg}`, `{:node_result, msg}`, `{:tool_call, msg, call}`, `{:resource_load, msg, resource}`, `{:job_complete, _}` and more to the caller process — handle them with `handle_info/2` in a LiveView or any GenServer. See `Agens.Backend` for the full list of callbacks.

---
**Sub-Jobs**

A Node can run an entire Sub-Job in place of inference by setting `:sub` to a Job id. When the Sub completes, the parent invokes the Node's Serving `c:Agens.Serving.handle_sub/3` callback to map the Sub's final `Agens.Message` into the parent Node's `outputs` and routing decision. A Serving can also emit `{:sub, job_id}` in its `next` list to chain a Sub-Job *after* its own inference. See the "Routing and Sub-Jobs" section in `Agens.Job` for details.

## Examples
The `examples/` directory contains:

- A single-file Phoenix LiveView app — see [`phoenix.exs`](examples/phoenix.exs) — wiring up `Instructor`, MCP tools, a PubSub backend, and a multi-node routed Job.
- Reference Serving implementations under `examples/servings/` (e.g. `Instructor` for structured outputs).
- A linear router and a condition-driven edge router under `examples/router/`.
- PubSub and file backends under `examples/backends/`.
- An MCP client/server pair under `examples/mcp/` using `hermes_mcp` for tools and resources.
- JSON-defined Jobs under `examples/jobs/`, loaded via `Agens.Job.Config.from_json/1`.

Run the Phoenix example with:

```bash
elixir examples/phoenix.exs
```

It will be available at [http://localhost:8080](http://localhost:8080).

## Name
The name Agens comes from the Latin word for 'Agents' or 'Actors.' It also draws from **intellectus agens**, a term in medieval philosophy meaning ['active intellect'](https://en.wikipedia.org/wiki/Active_intellect), which describes the mind's ability to actively process and abstract information. This reflects the goal of the Agens project: to create intelligent, autonomous agents that manage workflows within the Elixir ecosystem.

## License
This project is licensed under the Apache License, Version 2.0. See the [LICENSE](./LICENSE) file for more details.
