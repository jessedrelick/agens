defmodule Agens.Supervisor do
  @moduledoc """
  The Supervisor module for the Agens application.

  `Agens.Supervisor` starts a `DynamicSupervisor` for managing `Agens.Agent`, `Agens.Serving`, and `Agens.Job` processes. It also starts a `Registry` for keeping track of these processes.

  The Registry module can be overriden by your application config:

  ```elixir
  config :agens, registry: MyApp.Registry
  ```

  In order to use `Agens` simply add `Agens.Supervisor` to your application supervision tree:

  ```elixir
  Supervisor.start_link(
    [
      {Agens.Supervisor, name: Agens.Supervisor}
    ],
    strategy: :one_for_one
  )
  ```
  """
  use Supervisor

  @registry Application.compile_env(:agens, :registry)

  @doc false
  @spec start_link(any()) :: Supervisor.on_start()
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc false
  @impl true
  @spec init(any()) ::
          {:ok,
           {:supervisor.sup_flags(),
            [:supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
          | :ignore
  def init(_init_arg) do
    children = [
      {Agens, name: Agens},
      {Registry, keys: :unique, name: @registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
