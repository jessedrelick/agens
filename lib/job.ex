defmodule Agens.Job do
  use GenServer

  defmodule Config do
    defstruct [:name, :objective, :steps]
  end

  defmodule Step do
    defstruct [:agent, :prompt, :conditions]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  def child_spec(config) do
    %{
      id: config.name,
      start: {__MODULE__, :start_link, [config]},
      type: :worker,
      restart: :transient
    }
  end

  def init(config) do
    {:ok, config: config}
  end
end
