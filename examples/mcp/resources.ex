defmodule AgensDemo.Resources.Agens do
  use Hermes.Server.Component, type: :resource

  alias Hermes.Server.Response

  def uri, do: "agens://resources/agens"
  def name, do: "agens"
  def description, do: "High-level overview of Agens: what it is, what it is used for, and how it works"
  def mime_type, do: "text/plain"

  @impl true
  def read(_params, frame) do
    response =
      Response.resource()
      |> Response.text("""
      # Agens

      Agens is a multi-agent orchestration framework written in Elixir. It enables complex LLM
      workflows by composing Agents, Jobs, Nodes, and Servings into coordinated pipelines.

      ## Core Concepts

      **Serving** — Wraps a language model (or any inference backend). Implements `handle_message/3`
      to call the LLM and `handle_result/3` to parse the response into an `Agens.Serving.Result`.

      **Agent** — A named participant in a workflow. Each Agent is bound to a Serving and carries
      optional configuration (identity, persona, etc).

      **Job** — Defines a multi-step workflow as a directed graph of Nodes. A Job is started with
      an input and runs until a Node returns `:end` or an error occurs.

      **Node** — A single step within a Job. Specifies which Agent handles it, an optional
      objective, and optional Tool and Resource definitions.

      **Message** — The unit of data flowing through the pipeline. Carries the input,
      system/user prompts, LLM result, outputs, tool calls/results, and routing instructions.

      ## MCP Integration

      Nodes can be configured with:
      - **Tools** — functions the LLM can invoke during execution (e.g. database queries, API calls).
      - **Resources** — read-only data injected into the prompt as context before the LLM is called.
      """)

    {:reply, response, frame}
  end
end
