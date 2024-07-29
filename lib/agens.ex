defmodule Agens do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start(agents) when is_list(agents) do
    agents
    |> Enum.map(fn agent ->
      start_worker(agent)
    end)
  end

  def message(module, text) do
    case Process.whereis(module) do
      pid when is_pid(pid) ->
        Nx.Serving.batched_run(module, text)

      nil ->
        {:error, :agent_not_running}
    end
  end

  def start_worker(agent) do
    serving = agent.archetype

    spec = %{
      id: agent.name,
      start: {Nx.Serving, :start_link, [[serving: serving, name: agent.name]]}
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def stop_worker(module) do
    module
    |> Module.concat("Supervisor")
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :agent_not_found}

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  def start_job(config) do
    spec = Agens.Job.child_spec(config)
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
