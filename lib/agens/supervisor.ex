defmodule Agens.Supervisor do
  @moduledoc """
  The Supervisor module for the Agens application.

  `Agens.Supervisor` starts a `DynamicSupervisor` for managing `Agens.Agent`, `Agens.Serving`, and `Agens.Job` processes.

  In order to use `Agens` simply add `Agens.Supervisor` to your application supervision tree:

  ```
  Supervisor.start_link(
    [
      {Agens.Supervisor, name: Agens.Supervisor}
    ],
    strategy: :one_for_one
  )
  ```

  ### Options
    * `:prefixes` (`Agens.Prefixes`) - The default prompt prefixes can be overriden with this option. Each `Agens.Serving.Config` can also override the defaults on a per-serving basis.

  See the [README.md](README.md#configuration) for more info.
  """
  use Supervisor

  alias Agens.Prefixes

  @default_opts [prefixes: Prefixes.default()]

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :supervisor
    }
  end

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(args) do
    override = Keyword.get(args, :opts, [])
    opts = Keyword.merge(@default_opts, override)

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
    children = [
      {Agens, name: Agens, opts: opts}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
