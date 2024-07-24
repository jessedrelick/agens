defmodule Agens do
  @moduledoc """
  Documentation for `Agens`.
  """

  Application.put_env(:nx, :default_backend, EXLA.Backend)

  defmodule Agent do
    defstruct [:name, :archetype, :context, :knowledge]
  end

  def init() do
    serving = Agens.Archetypes.text_generation()

    Supervisor.start_link(
      [
        {Nx.Serving, serving: serving, name: Agens.SimpleServing, batch_timeout: 100}
      ],
      strategy: :one_for_one
    )
  end

  def message(text) do
    Nx.Serving.batched_run(Agens.SimpleServing, text)
  end
end
