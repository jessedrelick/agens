defmodule Agens do
  @moduledoc """
  Documentation for `Agens`.
  """

  alias Agens.Manager

  defmodule Agent do
    defstruct [:name, :archetype, :context, :knowledge]
  end

  def start(agents) when is_list(agents) do
    agents
    |> Enum.map(fn agent ->
      Manager.start_worker(agent)
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
end
