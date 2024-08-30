# Changelog

## 0.1.2
This release removes [application environment configuration](https://hexdocs.pm/elixir/1.17.2/design-anti-patterns.html#using-application-configuration-for-libraries) and moves to an opts-based configuration. See [README.md](README.md#configuration) for more info.

### Features
- Configure `Agens` via `Supervisor` opts instead of `Application` environment
- Add `Agent.get_config/1`
- Add `Serving.get_config/1`
- Support sending `Agens.Message` without `Agens.Agent`
- Override default prompt prefixes with `Agens.Serving`
- Serving child process?

### Fixes
- `Job.get_config/1` now wraps return value with `:ok` tuple `{:ok, Job.Config.t()}`
- Replaced `module() | Nx.Serving.t()` with `atom()` in `Agent.Config.t()` 

## 0.1.1
Initial release