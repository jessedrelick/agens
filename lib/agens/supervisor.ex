defmodule Agens.Supervisor do
  @moduledoc """
  The Supervisor module for the Agens application.

  `Agens.Supervisor` starts a `DynamicSupervisor` for managing `Agens.Agent`, `Agens.Serving`, and `Agens.Job` processes. It also starts a `Registry` for keeping track of these processes.

  The Registry module can be overriden by your application config:

  ```
  config :agens, registry: MyApp.Registry
  ```

  In order to use `Agens` simply add `Agens.Supervisor` to your application supervision tree:

  ```
  Supervisor.start_link(
    [
      {Agens.Supervisor, name: Agens.Supervisor}
    ],
    strategy: :one_for_one
  )
  ```
  """
  use Supervisor

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(args) do
    defaults = [registry: Agens.Registry]
    override = Keyword.get(args, :opts, [])
    opts = Keyword.merge(defaults, override)

    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  @spec init(keyword()) ::
          {:ok,
           {:supervisor.sup_flags(),
            [:supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
          | :ignore
  def init(opts) do
    registry = Keyword.fetch!(opts, :registry)
    children = [
      {Agens, name: Agens, opts: opts},
      {Registry, keys: :unique, name: registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
