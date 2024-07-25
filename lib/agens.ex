defmodule Agens do
  @moduledoc """
  Documentation for `Agens`.
  """

  alias Agens.{Archetypes, Manager}

  defmodule Agent do
    defstruct [:name, :archetype, :context, :knowledge]
  end

  def init() do
    Application.put_env(:nx, :default_backend, EXLA.Backend)
    Supervisor.start_link(
      [
        {Manager, name: Manager}
      ],
      strategy: :one_for_one
    )

    [
      %Agent{
        name: Agens.FirstAgent,
        archetype: Archetypes.text_generation(),
        context: "",
        knowledge: ""
      },
      %Agent{
        name: :another_agent,
        archetype: Archetypes.text_generation(),
        context: "",
        knowledge: ""
      }
    ]
    |> start()
  end

  def start(agents) when is_list(agents) do
    agents
    |> Enum.map(fn agent ->
      Manager.start_worker(agent)
    end)
  end

  def message(module, text) do
    Nx.Serving.batched_run(module, text)
  end
end
