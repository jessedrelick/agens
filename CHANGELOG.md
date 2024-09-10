# Changelog

## 0.1.3
This release introduces a [single-file Phoenix LiveView example](examples/phoenix.exs) that can be run with `elixir examples/phoenix.exs`.

In addition, this release removes the use of `Registry`, adds better error handling, and improves `GenServer` usage, including better child specs.

### Features
- Added `examples/phoenix.exs` example
- Added `Agens.Prefixes`
- Added pass-through `args` and `finalize` function to `Agens.Serving`
- Added `{:job_error, {job.name, step_index}, {:error, reason | exception}}` event to `Agens.Job`
- Added `Agens.child_spec/1` and `Agens.Supervisor.child_spec/1`
- Added `{:error, :job_already_running}` when calling `Agens.Job.run/2` on running job
- Added `{:error, :input_required}` when calling `Message.send/1` with empty `input`

### Breaking Changes
- Removed `Registry` usage and `registry` configuration option
- Changed `prompts` to `prefixes` on `Agens.Serving.Config`

### Fixes
- Removed `restart: :transient` from `Agens.Serving.child_spec/1` and `Agens.Agent.child_spec/1`

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