defmodule Agens.Supervisor do
  @moduledoc """
  The Supervisor module for the Agens application.
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
  @spec init(any()) :: {:ok, Supervisor.supervisor()}
  def init(_init_arg) do
    children = [
      {Agens, name: Agens},
      {Registry, keys: :unique, name: @registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
