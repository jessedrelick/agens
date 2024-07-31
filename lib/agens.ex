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
      start_agent(agent)
    end)
  end

  def message(agent_name, text) do
    case Registry.lookup(Agens.Registry.Agents, agent_name) do
      [{_, {agent_pid, agent_config}}] when is_pid(agent_pid) ->
        Nx.Serving.batched_run(agent_name, text)

      [] ->
        {:error, :agent_not_running}
    end
  end

  def start_agent(agent) do
    spec = %{
      id: agent.name,
      start: {Nx.Serving, :start_link, [[serving: agent.serving, name: agent.name]]}
    }

    {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, spec)
    Registry.register(Agens.Registry.Agents, agent.name, {pid, agent})
    {:ok, pid}
  end

  def stop_agent(name) do
    name
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
