defmodule AgensDemo.LinearRouter do
  use Agens.Router

  alias Agens.Message

  @impl Agens.Router
  def outputs(%Message{}), do: []

  @impl Agens.Router
  def resolve(%Message{job_id: job_id, node_id: node_id}, _outputs) do
    case Enum.find_index(nodes(job_id), &(&1 == node_id)) do
      nil -> [:end]
      idx ->
        case Enum.at(nodes(job_id), idx + 1) do
          nil -> [:end]
          next -> [{:route, next, 1}]
        end
    end
  end

  defp nodes("industry_brief"), do: ["planner", "researcher", "writer"]
  defp nodes(_), do: []
end
