defmodule Agens.Supervisor do
  @moduledoc """
  The Supervisor module for the Agens application.

  `Agens.Supervisor` starts a `DynamicSupervisor` for managing `Agens.Serving` and `Agens.Job` processes.

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
  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc false
  @impl true
  @spec init(:ok) ::
          {:ok,
           {:supervisor.sup_flags(),
            [:supervisor.child_spec() | (old_erlang_child_spec :: :supervisor.child_spec())]}}
          | :ignore
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: Agens.Registry},
      {Task.Supervisor, name: Agens.JobSupervisor},
      {Agens, name: Agens}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
