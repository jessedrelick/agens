defmodule AgensDemo.AgensRouter do
  use Agens.Router

  alias Agens.Message

  @impl Agens.Router
  def outputs(%Message{job_id: job_id}) do
    Application.get_env(:agens_demo, {:job_outputs, job_id}, [])
  end

  @impl Agens.Router
  def resolve(message, merged_outputs) do
    message
    |> edges()
    |> AgensRouter.Edge.get(merged_outputs)
  end

  defp edges(%Message{job_id: job_id, node_id: node_id}) do
    :agens_demo
    |> Application.get_env({:job_edges, job_id}, %{})
    |> Map.get(node_id, [%AgensRouter.Edge{type: :end}])
  end
end
