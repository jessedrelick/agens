defmodule AgensDemo.LinearRouter do
  use Agens.Router

  alias Agens.Message

  @impl Agens.Router
  def outputs(%Message{}), do: []

  @impl Agens.Router
  def resolve(%Message{job_id: job_id, node_id: node_id}, _outputs) do
    nodes = Application.get_env(:agens_demo, {:linear_nodes, job_id}, [])

    case Enum.find_index(nodes, &(&1 == node_id)) do
      nil -> [:end]
      idx ->
        case Enum.at(nodes, idx + 1) do
          nil -> [:end]
          next -> [{:route, next, 1}]
        end
    end
  end
end
