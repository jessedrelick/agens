defmodule Agens do
  @moduledoc """
  Documentation for `Agens`.
  """

  defmodule Agent do
    defstruct [:name, :archetype, :context, :knowledge]
  end

  defmodule Manager do
    use DynamicSupervisor

    def start_link(_) do
      DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
    end

    def init(:ok) do
      DynamicSupervisor.init(strategy: :one_for_one)
    end

    def start_worker(agent) do
      serving = agent.archetype.init()
      spec = %{
        id: agent.name,
        start: {Nx.Serving, :start_link, [[serving: serving, name: agent.name]]}
      }

      {:ok, pid} = DynamicSupervisor.start_child(__MODULE__, spec)
      {:ok, _owner} = Registry.register(Registry.Agents, agent.name, pid)
      {:ok, pid}
    end

    def stop_worker(pid) do
      DynamicSupervisor.terminate_child(__MODULE__, pid)
    end

    def message(id, msg) do
      case Registry.lookup(Registry.Agents, id) do
        [{pid, _}] when is_pid(pid) -> send(pid, msg)
        _ -> :agent_not_found
      end
    end
  end


  @doc """
  Hello world.

  ## Examples

      iex> Agens.hello()
      :world

  """
  def hello do
    Manager.message(:first_agent, "hello")
  end

  def example() do
    init()

    [
      %Agent{
        name: :first_agent,
        archetype: Agens.Archetypes.TextGeneration,
        context: "",
        knowledge: ""
      }
    ]
    |> start()
  end

  def init() do
    Registry.start_link(keys: :unique, name: Registry.Agents)
    Manager.start_link([])
    Manager.init(:ok)
  end

  def start(agents) when is_list(agents) do
    agents
    |> Enum.map(fn agent ->
      Manager.start_worker(agent)
    end)
  end
end
