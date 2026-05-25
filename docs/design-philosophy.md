# Design Philosophy

Agens is intentionally small. The framework owns multi-agent *orchestration* — Jobs, Nodes, Routers, queues, retries, telemetry — and leaves most everything else to the host application. This document explains the principles behind that boundary: why the core is thin, where the extension points live, and which tradeoffs are accepted on purpose.

For the practical side of the boundary — what you write versus what Agens runs — see [Host Application Responsibilities](host-responsibilities.md).

## Lightweight by design

### Showcase Elixir and OTP for multi-agent workflows

Agens exists, in part, to demonstrate that the BEAM is a natural home for multi-agent LM workflows. Most of what other frameworks reinvent — supervised processes per Job run, bounded concurrency per Serving, parallel fan-out and aggregation, telemetry spans, crash isolation, hot restarts — is already provided by OTP. Agens is a thin layer over `GenServer`, `DynamicSupervisor`, `Task.Supervisor`, `Registry`, and `:telemetry`. The result is a smaller surface area than the Python-ecosystem analogs because so much of the hard infrastructure is solved one layer down.

This shapes the API. `Agens.Serving` is a `GenServer` with a FIFO queue and a configurable in-flight limit. `Agens.Job` is a supervised process per `run_id`. Sub-Jobs are nested supervised processes, not abstract workflow primitives. Parallel routing is built on `Task.Supervisor.async_stream`. The framework leans on what the BEAM already does well rather than re-implementing it.

### Adapter-less core

Agens ships no LM provider modules. There is no `Agens.OpenAI`, no `Agens.Anthropic`, no `Agens.Ollama`. Provider integration lives in your Serving's `c:Agens.Serving.handle_message/3` — typically a thin HTTP call or `Nx.Serving` invocation. Examples under `examples/servings/` exist as reference implementations, not as part of the framework.

The same approach extends to tool calls. Most frameworks wire each provider's native tool-call API behind a provider-specific adapter — OpenAI's `tool_calls` array, Anthropic's `tool_use` blocks, Gemini's function declarations — and the shapes differ enough that the adapter layer is where a large fraction of provider-coupled code lives. Agens skips the layer entirely: tool calls are declared as part of the Serving's structured-output schema and surface in the LM's normal JSON response, alongside whatever other outputs the Router declared.

The runtime hands those tool calls to `c:Agens.Serving.tool_call/3` and merges the results back into the next prompt under the `Tool Results` prefix. Resources work the same way — loaded by `c:Agens.Serving.load_resource/3` before inference, content surfaced under the `Resources` prefix. The result is a tool/resource layer that's identical across providers because it never touches a provider-specific tool-call format.

Agens borrows the MCP (Model Context Protocol) *shape* — tools as JSON schemas with name/description/parameters, resources as URI/name/description records — but ships no MCP client and no per-provider adapter. The host wires whatever it likes (HTTP, an MCP client like `hermes_mcp`, local Elixir code, a database query) inside the callback.

This is the most deliberate scope choice in the project. Provider adapters are where frameworks accumulate the most code, drift the fastest, and tie users most tightly to the framework's release cadence. Keeping that surface out of the core means Agens stays small, releases independently from provider API churn, and never forces a Serving to fight a leaky abstraction.

### Avoid the framework-bloat trap

Many LM frameworks accumulate vector stores, embedding integrations, document loaders, memory abstractions, agent persona helpers, prompt template libraries, and more. Each addition pulls in dependencies, ships opinions, and grows the maintenance surface. Agens stays in the orchestration lane. If you need a vector store, you pick one; if you need persona handling, you store it under your `:agent_id` and load it in `c:Agens.Serving.load_context/2`; if you need conversation history, you persist it via a backend and reload it the same way. The host responsibilities doc enumerates what's deliberately out of scope.

## Extensible and unopinionated

Every place where opinions would normally live — provider choice, prompt shape, validation rules, routing strategy, persistence — is exposed as a behaviour or override point. Defaults exist where a sensible default is genuinely possible; where it isn't, the seam is explicit.

### Backends: one behaviour for everything

`Agens.Backend` is the single extension point for *both* observability and persistence. The same chain of backends receives every lifecycle, Node, tool, resource, and Sub event in declaration order. You can wire a PubSub dispatcher next to a database writer next to an OpenTelemetry exporter without the framework caring which is which. Shipped defaults (an in-process emit backend and a structured-log backend) cover development and basic logging; everything else is the host's call.

### Serving callbacks

A Serving is a `use Agens.Serving` module with a few callbacks. `c:Agens.Serving.handle_message/3` is the LM call. `c:Agens.Serving.handle_result/3` is where validation lives — return `{:ok, result}`, `{:retry, reason}`, or `{:error, reason}` and the runtime does the rest. `c:Agens.Serving.load_context/2`, `c:Agens.Serving.load_resource/3`, and `c:Agens.Serving.tool_call/3` are the seams for per-agent context, resource fetching, and tool execution. Each callback has a narrow job; the framework composes them into a Node run.

### Prefix and prompt construction overrides

Prompt assembly is layered so most workflows never touch it, and the ones that do reach for the lightest layer that works. `Agens.Prefixes.default/0` ships sensible section headings and detail strings. `:prefixes` on `Agens.Serving.Config` overrides specific sections. `c:Agens.Serving.build_prompt/3` replaces the assembly entirely (e.g. for a chat-message format with role labels). Schema callbacks (`outputs_schema/1`, `tools_schema/1`, `response_schema/1`, `build_schema/1`) give graduated control over the JSON schema sent to the LM. The layering matters: a one-line `:prefixes` override is much cheaper to maintain than a custom `build_prompt/3`.

### Routing as a behaviour, not a primitive

`Agens.Router` is the same behaviour whether you want graph-based edges (`examples/router/edge_router.ex`), step-based linear flow (`examples/router/linear_router.ex`), or LM-driven dynamic routing where the Serving returns a `next` field. The Router decides per-request from the running `Agens.Message` and the structured outputs; nothing about flow is baked into static Node configuration. Picking a routing paradigm is a host decision made per Job or per Node, not a framework decision made up front.

### Tools and Resources as schemas, not implementations

Tools attach to a Node via `:tools` and surface in the prompt under the `Tool Definitions` prefix. Resources attach via `:resources` and are loaded before inference by `c:Agens.Serving.load_resource/3`. The framework knows the *shape* — what the LM sees, where the results go in the next prompt — but never the substance. There is no tool registry, no resource cache, no per-protocol marshalling. If you want to wire `hermes_mcp`, hit an HTTP API, read a file, query a vector DB, or run local Elixir, the callback is the same.

## Challenges and honest tradeoffs

A small unopinionated core is not free. Three tensions are worth naming explicitly.

### Structured outputs vs. native tool-call APIs

Surfacing tool calls through the structured-output schema is what lets Agens stay provider-agnostic, but native tool-call APIs are typically more reliable on the provider side. Models are fine-tuned to use them, and providers return them through a dedicated, strongly-typed channel rather than as fields inside a free-form JSON response. Asking the same model to emit tool calls as part of a JSON-schema-constrained output works — especially with strict-mode structured outputs — but it leans harder on the LM following the schema than on a dedicated API contract. For workflows where tool reliability is the top constraint, a more opinionated framework with first-class adapters per provider may fit better; for workflows where provider portability matters more, the structured-outputs approach trades a small reliability gap for a much smaller adapter surface.

### MCP-shape, not MCP-protocol

Agens uses MCP's data shape for tools and resources but doesn't implement the protocol. There's no JSON-RPC layer, no MCP server lifecycle management, no built-in client. This keeps the core protocol-agnostic and lets the host pick any MCP implementation — or skip MCP entirely.

It also concedes something. The MCP shape works cleanly for tools (loose coupling, JSON in / JSON out) but is more opinionated for resources, where URI/name/description doesn't map perfectly onto every alternative (LangChain-style document loaders, vector-store retrievers with metadata filters, etc.). The aspiration is a tool/resource layer that can host alternative protocols without forcing them through the MCP-shaped door; today that's an accepted limitation.

### Unopinionated routing has costs

Routing is dynamic per-request, decided by `c:Agens.Router.resolve/2`. There is no first-class edge primitive on `Agens.Job.Node` — no `from: A, to: B, when: ...` field — and no static graph the framework can inspect ahead of a run. Users coming from LangGraph or CrewAI have to build their own edge abstraction on top of the Router behaviour. The reference `examples/router/edge_router.ex` demonstrates one approach but is example code, not framework code.

The tradeoff cuts both ways. The Router can express any routing strategy the host can write — including ones that read context, branch on retrieved data, or hand flow control to the LM — and the same behaviour covers graph, sequential, and dynamic paradigms uniformly. The cost is that simple cases require more code than a declarative `next: "node_b"` field would, and that there's no out-of-the-box way to render a Job's flow as a static diagram. A future iteration may add an optional edge layer over the Router for cases where a declarative shape would carry its weight.

## Summary

Agens is built around a small bet: that the BEAM's primitives are most of what multi-agent orchestration needs, and that the LM/tool/resource layer above them is too varied to encode opinions about. The framework owns the protocol — Job lifecycles, Node routing, queues, retries, telemetry — and leaves the substance to the host. Where defaults exist, they're sensible; where they don't, the seam is small, named, and documented. The cost is that simple cases sometimes take more code than a more opinionated framework would require; the benefit is that the framework doesn't get in your way once you outgrow those simple cases.
