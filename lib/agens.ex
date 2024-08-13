defmodule Agens do
  use DynamicSupervisor

  defmodule Message do
    defstruct [
      :parent_pid,
      :input,
      :prompt,
      :result,
      :agent_name,
      :serving_name,
      :job_name,
      :step_index
    ]
  end

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
