# Host Application Responsibilities

Agens is intentionally narrow. It handles the *orchestration* of multi-agent workflows — Job lifecycles, Node routing, Sub-Job composition, concurrency control, retries, telemetry — but stays out of every concern that's specific to your application: the LM provider, tool execution, persistence, UI, and the substantive content of your prompts. This document describes the boundary so you can scope what to build before adopting Agens.

## What Agens handles

### Orchestration

- **Job lifecycle** — supervised process per Job run; status transitions (`init` → `running` → `complete` / `ended` / `error` / `stopped`); explicit `Agens.Job.stop/1` cancellation.
- **Node routing** — every transition between Nodes is decided at runtime by the Serving's Router based on the LM's structured response.
- **Parallel routing primitives** — fan-out (`{:route, node_id, count}`), aggregation (`{:yield, node_id}`), retries bounded by `:max_retries`, explicit termination (`:end`).
- **Sub-Job composition** — hierarchical Job nesting (in-place-of-inference or routed-to work).
- **Run-id-keyed parallel execution** — the same `Agens.Job.Config` can be started many times with distinct `run_id`s.
- **Crash isolation** — per-Node inference runs in supervised tasks.

### Serving runtime

- **FIFO queue + concurrency limit** — bounded in-flight requests per Serving (`use Agens.Serving, limit: N`).
- **Timeout enforcement** — per-Serving timeout via `Agens.Serving.Config.timeout`.
- **Prompt assembly** — `Agens.Prompt.build/3` stitches `Agens.Message` fields into system/user prompt pairs using the configured `Agens.Prefixes`.
- **Structured-output schema assembly** — JSON schema built per-request from the Router's declared `Agens.Router.Output` list.
- **Retry loop** — when the Serving returns `{:retry, reason}` or the Router returns `[:retry]` / `[{:retry, reason}]`, the runtime bumps the retry count, injects the reason under the `Retry` prefix, and re-runs the Node up to `Agens.Job.Config.max_retries`.

### Observability

- **Telemetry events** — comprehensive coverage of Job/Node/Sub/Serving/tool/resource lifecycle (see `Agens.Metrics.metrics/0`).
- **Backend dispatch** — every significant event fans out to all configured `Agens.Backend` modules in declaration order.

## What the host handles

### Application setup

- Add `{Agens.Supervisor, name: Agens.Supervisor}` to your supervision tree.
- Configure backends via the `:agens` app env (or accept the defaults).
- Start each Serving at application boot via `Agens.Serving.start/1`.

### LM integration (Servings)

Each Serving is a module that `use`s `Agens.Serving`. The host writes:

- **`c:Agens.Serving.handle_message/3`** — the actual HTTP call (or `Nx.Serving` / `Bumblebee` invocation) to your LM provider, returning `{:ok, parsed}` or `{:error, reason}`. API keys, request shaping, and provider-specific quirks live here.
- **`c:Agens.Serving.handle_result/3`** — convert the parsed response into an `Agens.Serving.Result` with `:body`, `:outputs`, `:tool_calls`, optionally `:next`. Can also return `{:retry, reason}` to trigger a validation-driven retry (see "Validation and retries" below).
- **`c:Agens.Serving.load_context/2`** (optional) — given the Message's `:agent_id`, return per-agent context (system prompt, persona, retrieved memory) for injection into the prompt. **Also where you load conversation history** for multi-turn chat Servings (see "Message history" below).

### Routing logic (Routers)

A Router (merged into a Serving or split as a separate module) implements:

- **`c:Agens.Router.outputs/1`** — declares the structured-output schema the LM should emit (a list of `Agens.Router.Output` definitions). Drives both validation and routing.
- **`c:Agens.Router.resolve/2`** — given the populated outputs, return route instructions.

**Routing is multi-paradigm by design.** The same `Agens.Router` behaviour supports:

- **Graph-based routing** — declared edges with `Agens.Router.Condition` matching against structured outputs (see `examples/router/edge_router.ex`).
- **Step-based / sequential routing** — linear next-pointer logic via Node-id position lookup (see `examples/router/linear_router.ex`).
- **LM-driven dynamic routing** — the Serving returns a `next` field on its `Agens.Serving.Result`, decoded by `Agens.Router.parse_next/1` and used in place of the Router's static resolution.

Routers can also combine paradigms: `route/2` (injected by `use Agens.Router`) accepts an LM-supplied dynamic `next` and falls back to static `route/1` resolution when the LM doesn't provide one. You pick the paradigm per Job or per Node based on how much agency the LM should have over flow control.

### Validation and retries

The host controls when an LM response is "good enough" through `c:Agens.Serving.handle_result/3`. Three return shapes:

- `{:ok, %Agens.Serving.Result{...}}` — the response passed your validation; continue to routing.
- `{:retry, reason}` — the response failed your validation; the runtime increments the retry counter and re-runs the Node with `reason` injected under the `Retry` prefix in the next prompt. Capped by `Agens.Job.Config.max_retries`.
- `{:error, reason}` — hard error; the Job terminates via the normal error path.

This is the seam for custom validation. If the LM emits malformed structured output, fails a domain-specific business rule, or returns an answer your application can't accept, return `{:retry, "your-validation-message-here"}` and the next attempt sees the message verbatim in its prompt. The LM correcting itself based on retry reasons is one of the strongest patterns the framework enables.

### MCP integration (Tools and Resources)

Agens models tool calls and resources after the MCP (Model Context Protocol) shape — tools as JSON schemas declared per-Node, resources as URI/name/description records. Agens routes the protocol; the host implements the substance:

- **Tool definitions** — populate `Agens.Job.Node.tools` with MCP-style tool schemas. Agens surfaces them under the `Tool Definitions` prefix in the LM prompt.
- **Tool execution (`c:Agens.Serving.tool_call/3`)** — when the LM emits `tool_calls`, Agens invokes this callback for each one. The host writes the actual tool effect (calling out to an MCP server, hitting an HTTP API, executing local code, querying a database). Returns `{tool_id, result}` or `{:error, reason}`; results are merged back into the next prompt under `Tool Results`.
- **Resource declarations** — populate `Agens.Job.Node.resources` with `Agens.Resource` structs (URI, name, optional description).
- **Resource loading (`c:Agens.Serving.load_resource/3`)** — Agens calls this for each declared resource before inference. The host writes the fetch (file read, vector DB lookup, MCP `resources/read` call, HTTP GET) and returns a `Resource` with `:content` populated. Loaded content is surfaced under the `Resources` prefix.

Agens stays MCP-agnostic — there's no built-in MCP client, no JSON-RPC handling, no MCP server lifecycle management. Agens just provides the schema shapes and the per-Node attachment points.

For a reference implementation showing one end-to-end approach, see the `examples/mcp/` directory in the repository. It pairs a `hermes_mcp`-based MCP server (`examples/mcp/server.ex`) with a matching client (`examples/mcp/client.ex`) and demonstrates wiring both into Agens via the `c:Agens.Serving.tool_call/3` and `c:Agens.Serving.load_resource/3` callbacks.

### Prompt customization

Sensible defaults ship out of the box: `Agens.Prefixes.default/0` returns a struct with reasonable headings and detail for every prompt section (Job description, Node objective, Context, Input, Previous Result, Tool Definitions, Tool Calls, Tool Results, Resources, Schema, Retry), and `Agens.Prompt.build/3` handles assembly with a sensible system/user partition. Most workflows can run the defaults unchanged and only revisit this surface when they need to.

When you do need to customize, the surface is layered — use the lightest layer that meets the need:

- **Heading / detail per section** — set `:prefixes` on `Agens.Serving.Config` to a custom `Agens.Prefixes` struct (typically start from `Agens.Prefixes.default/0` and override select fields). Right for cosmetic tweaks, swapping the prompt's language, or aligning headings with a house style.
- **Full prompt construction** — override `c:Agens.Serving.build_prompt/3` to produce any string shape you need (e.g. a chat-message format with role labels for Anthropic, instead of system/user concatenation for OpenAI).
- **Schema customization** — override `c:Agens.Serving.outputs_schema/1`, `c:Agens.Serving.tools_schema/1`, `c:Agens.Serving.response_schema/1`, or `c:Agens.Serving.build_schema/1` for control over the JSON schema sent to the LM. The default `outputs_schema/1` returns an empty placeholder; most Servings override it to derive the schema from the Router's declared `Agens.Router.Output` list (see `examples/servings/instructor_serving.ex`).

The layering matters: a one-line `:prefixes` override is much cheaper to maintain than a custom `build_prompt/3`, and a custom schema callback is much cheaper than a full `build_schema/1`. Reach for the deeper override only when the lighter one can't express what you need.

### Message history

Conversation history loading is the host's responsibility and the most easily-overlooked one. Agens does not store messages across runs — each `Agens.Job.run/3` invocation starts from a clean slate. For turn-based / multi-turn Servings:

- Persist messages externally (database, file, in-memory cache) via a custom backend that listens to `:node_result` events.
- Load prior turns inside `c:Agens.Serving.load_context/2` (or `c:Agens.Serving.handle_message/3` directly) — typically keyed by `run_id`, `parent_run_id`, or your own conversation identifier carried via `agent_id`.
- Inject the loaded history into the LM call as you see fit — usually as additional `assistant` messages prepended to the current user prompt.

This is one of the rare areas where the boundary deliberately leaves a load-bearing concern to the host: Agens has no opinion on how your conversation state should be modeled.

### Job authoring

- Construct `Agens.Job.Config` (programmatically or via `from_json/1`) with a `nodes` map and `:starting_node_id`. Each Node references a Serving by name and optionally declares `:agent_id`, `:objective`, `:tools`, `:resources`, or a `:sub` Sub-Job id.
- Generate a unique `run_id` (typically `Agens.generate_uid/0`), call `Agens.Job.start/2` to supervise the process, then `Agens.Job.run/3` to begin execution.

### Backends: observability AND persistence

The `Agens.Backend` behaviour is the single extension point for *both* observability and persistence. This dual role is worth calling out explicitly because it's easy to assume Agens has separate hooks for "logging-style side effects" and "storing-things side effects" — it doesn't, and you'll typically write at least one of each:

- **Observability backends** — forward events to your logger, PubSub topic, OpenTelemetry exporter, LiveView dispatcher, etc. The shipped defaults (an in-process emit backend and a structured-log backend) are both observability flavored.
- **Persistence backends** — write `node_result`, `tool_call`, `resource_load`, and lifecycle events to your application's storage so you can audit runs, build chat history, or resume from checkpoints.

Backends are chainable: every configured backend receives every event in declaration order. A typical configuration has one observability backend (PubSub or LiveView dispatch) and one persistence backend (writes to your DB or file system).

For metrics specifically, attach a `Telemetry.Metrics.Reporter` (Prometheus, StatsD) to `Agens.Metrics.metrics()` — that's a separate, complementary mechanism that doesn't go through `Agens.Backend`.

### Sub-Job resolution

If you use Sub-Jobs, at least one configured backend must implement `c:Agens.Backend.sub/1` to return an `Agens.Job.Sub` for a given `job_id`. This is where the host decides how `job_id`s map to Sub-Job configurations.

### Domain concerns Agens does not address

- LM provider details — API keys, rate limiting, cost tracking, model selection.
- UI / transport — Phoenix LiveView, CLI, websockets, channels.
- Authentication / authorization.
- Higher-level retry/backoff policies across full Job runs.
- Tool registry / discovery.
- MCP client/server protocol — Agens uses the MCP shape but doesn't implement the protocol itself.

## Summary

The clean way to think about it: **Agens owns the protocol; the host owns the substance.** Agens runs the state machine that turns LM responses into Node transitions, but every "what does this Node actually do" decision — which model to call, how to fetch this resource, what this tool means, when an answer is valid — is yours.
