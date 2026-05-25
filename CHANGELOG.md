# Changelog

## 0.2.0 (2026-05-22)
A substantial redesign of the framework around dynamic routing, MCP-shaped tools/resources, and a pluggable backend layer. Jobs are now a list of `Agens.Job.Node`s instead of a sequence of `Step`s, routing is decided per-request by an `Agens.Router` on top of structured outputs, and observability/persistence are unified under the `Agens.Backend` behaviour. The framework is intentionally adapter-less: LM provider integration lives in your Serving's `c:Agens.Serving.handle_message/3` callback, and tool calls are surfaced through the structured-output schema rather than per-provider tool-call APIs.

See [Host Application Responsibilities](docs/host-responsibilities.md) and [Design Philosophy](docs/design-philosophy.md) for the new boundaries and the reasoning behind them.

### Features
- Added `Agens.Job.Node` — graph nodes referencing a Serving, with optional `:agent_id`, `:objective`, `:tools`, `:resources`, and `:sub` (Sub-Job) fields.
- Added `Agens.Router` behaviour with `c:Agens.Router.outputs/1` and `c:Agens.Router.resolve/2`. Supports graph-based, sequential, and LM-driven dynamic routing through a single behaviour. See `examples/router/`.
- Added `Agens.Router.Output` and `Agens.Router.Condition` for declaring structured-output schemas and branching on them.
- Added parallel routing primitives: `{:route, node_id, count}` for fan-out, `{:yield, node_id}` for aggregation, `{:sub, job_id}` for chained Sub-Jobs, `:end` for explicit termination, and `:retry` (or `{:retry, reason}`) for validation-driven retries.
- Added `Agens.Job.Sub` and Sub-Job composition. A Node can run a Sub-Job in place of inference (mapped back via `c:Agens.Serving.handle_sub/3`) or chain one after inference via `{:sub, job_id}`.
- Added `Agens.Backend` behaviour as the single extension point for observability and persistence. Backends are chainable; every configured backend receives every lifecycle/Node/tool/resource/Sub event in declaration order.
- Added default backends: an in-process emit backend (sends events to the caller process) and a structured-log backend.
- Added `Agens.Resource` struct for MCP-shaped resources (URI, name, optional description, content).
- Added per-Serving FIFO queue and configurable in-flight limit via `use Agens.Serving, limit: N`.
- Added per-Serving timeout enforcement via `Agens.Serving.Config.timeout`.
- Added validation-driven retry loop: `c:Agens.Serving.handle_result/3` can return `{:retry, reason}` to re-run the Node with the reason injected under the `Retry` prefix, bounded by `Agens.Job.Config.max_retries`.
- Added MCP-shaped tools and resources. Tools attach per-Node via `:tools` and are executed by `c:Agens.Serving.tool_call/3`; resources attach via `:resources` and are loaded by `c:Agens.Serving.load_resource/3`.
- Added strict structured outputs — JSON schema assembled per-request from the Router's declared `Agens.Router.Output` list, compatible with OpenAI strict mode and similar grammar-constrained sampling.
- Added layered prompt customization: `Agens.Prefixes` (heading/detail per section), `c:Agens.Serving.build_prompt/3` (full prompt construction), and `outputs_schema/1`/`tools_schema/1`/`response_schema/1`/`build_schema/1` (schema customization).
- Added `Agens.Metrics` with comprehensive `Telemetry.Metrics` definitions covering Job, Node, Sub, Serving, tool, and resource lifecycle.
- Added `Agens.Job.Config.from_json/1` for JSON-defined Job configurations.
- Added `run_id`-keyed parallel execution. The same `Agens.Job.Config` can be started many times with distinct `run_id`s via `Agens.Job.start/2` + `Agens.Job.run/3`.
- Added MCP example under `examples/mcp/` using `hermes_mcp` for a working tool/resource server + client.
- Added [Host Application Responsibilities](docs/host-responsibilities.md) and [Design Philosophy](docs/design-philosophy.md) documentation.

### Breaking Changes
- Removed `Agens.Agent` module. `agent_id` survives as an opaque `binary()` identifier used by `c:Agens.Serving.load_context/2`.
- Removed `Agens.Job.Step`. Jobs are now a map of `Agens.Job.Node`s with a designated `:starting_node_id`, not a sequence of Steps.
- Removed static `:next` field from Nodes. Routing is dynamic and decided per-request by the Serving's Router.
- Removed first-class Bumblebee / `Nx.Serving` integration. Both are still supported through `c:Agens.Serving.handle_message/3` like any other LM, but no longer ship as built-in adapters.
- Removed `:prefixes` option from `Agens.Supervisor`. Set prefixes per-Serving via `Agens.Serving.Config`.
- Changed Job addressing: `Agens.Job.start/2` now takes a `run_id` and `Agens.Job.run/3` begins execution. Jobs are addressed by `run_id`, not name.
- Changed observability: lifecycle events now flow through the `Agens.Backend` behaviour instead of a single emit target. Defaults preserve the prior emit-to-caller behaviour.
- Changed tool calls: now configured per-Node via `:tools` and executed by `c:Agens.Serving.tool_call/3`, modeled after MCP tool calls.
- Changed identifiers from `any()` to `binary()` across `job_id`, `run_id`, `agent_id`, and Node ids.
- Removed `finalize` from `Agens.Serving.Config` in favor of Serving callbacks.

## 0.1.3
This release introduces a [single-file Phoenix LiveView example](examples/phoenix.exs) that can be run with `elixir examples/phoenix.exs`.

In addition, this release removes the use of `Registry`, adds better error handling, and improves `GenServer` usage, including better child specs.

### Features
- Added `examples/phoenix.exs` example
- Added `Agens.Prefixes`
- Added pass-through `args` and `finalize` function to `Agens.Serving`
- Added `{:job_error, {job.name, step_index}, {:error, reason | exception}}` event to `Agens.Job`
- Added child specs to `Agens` and `Agens.Supervisor`
- Added `{:error, :job_already_running}` when calling Agens.Job.run/2 on running job
- Added `{:error, :input_required}` when calling `Message.send/1` with empty `input`

### Breaking Changes
- Removed `Registry` usage and `registry` configuration option
- Changed `prompts` to `prefixes` on `Agens.Serving.Config`
- Added `input` to `@enforce_keys` and removed `nil` as accepted `input` type in `Agens.Message`

### Fixes
- Removed `restart: :transient` from `Agens.Serving` and `Agens.Agent` child specs

## 0.1.2
This release removes [application environment configuration](https://hexdocs.pm/elixir/1.17.2/design-anti-patterns.html#using-application-configuration-for-libraries) and moves to an opts-based configuration. See [README.md](README.md#configuration) for more info.

### Features
- Configure `Agens` via `Supervisor` opts instead of `Application` environment
- Add `Agens.Agent.get_config/1`
- Add `Agens.Serving.get_config/1`
- Support sending `Agens.Message` without `Agens.Agent`
- Override default prompt prefixes with `Agens.Serving`

### Fixes
- `Agens.Job.get_config/1` now wraps return value with `:ok` tuple: `{:ok, Agens.Job.Config.t()}`
- Replaced `module() | Nx.Serving.t()` with `atom()` in `Agens.Agent.Config.t()` 

## 0.1.1
Initial release