defmodule Agens.Job do
  use GenServer

  defmodule Config do
    defstruct [:name, :objective, :steps]
  end

  defmodule Step do
    defstruct [:agent, :prompt, :conditions]
  end

  defmodule State do
    defstruct [:config]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config.name)
  end

  def child_spec(config) do
    %{
      id: config.name,
      start: {__MODULE__, :start_link, [config]},
      type: :worker,
      restart: :transient
    }
  end

  def get_config(pid) when is_pid(pid), do: GenServer.call(pid, :get_config)

  def get_config(name) when is_atom(name) do
    name
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :job_not_found}

      pid when is_pid(pid) ->
        get_config(pid)
    end
  end

  def init(config) do
    {:ok, %State{config: config}}
  end

  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end
end
