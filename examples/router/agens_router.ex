defmodule AgensDemo.AgensRouter do
  use AgensRouter

  alias Agens.Message

  @impl AgensRouter
  def outputs(%Message{job_id: job_id}) do
    Application.get_env(:agens_demo, {:job_outputs, job_id}, [])
  end

  @impl AgensRouter
  def edges(%Message{job_id: job_id, node_id: node_id}) do
    :agens_demo
    |> Application.get_env({:job_edges, job_id}, %{})
    |> Map.get(node_id, [%AgensRouter.Edge{type: :end}])
  end
end
