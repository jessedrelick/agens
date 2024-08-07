defmodule Agens do
  use DynamicSupervisor

  alias Agens.Agent

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

  def message(agent_name, input) do
    case Registry.lookup(Agens.Registry.Agents, agent_name) do
      [{_, {agent_pid, agent_config}}] when is_pid(agent_pid) ->
        base = Agent.base_prompt(agent_config, input)
        prompt = "<s>[INST]#{base}[/INST]"
        serving = agent_config.serving

        %{results: [%{text: text}]} =
          cond do
            is_atom(serving) ->
              GenServer.call(agent_pid, {:run, prompt, input})

            # GenServer.call(agent_name, {:run, input})
            # apply(serving, :run, [input])

            %Nx.Serving{} = serving ->
              Nx.Serving.batched_run(agent_name, prompt)
          end

        result = Agent.maybe_use_tool(agent_config.tool, text)

        {:ok, result}

      [] ->
        {:error, :agent_not_running}
    end
  end

  def start_agent(agent) do
    spec = %{
      id: agent.name,
      start: start_function(agent)
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

  defp start_function(%Agent{serving: %Nx.Serving{} = serving} = agent) do
    {Nx.Serving, :start_link, [[serving: serving, name: agent.name]]}
  end

  defp start_function(%Agent{serving: serving} = agent) do
    {serving, :start_link, [[name: agent.name, config: agent]]}
  end
end
