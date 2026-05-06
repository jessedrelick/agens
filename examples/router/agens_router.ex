defmodule AgensDemo.AgensRouter do
  use Agens.Router

  alias Agens.{Message, Router.Condition}

  defmodule Edge do
    @type t :: %__MODULE__{
            type: :route | :fallback | :yield | :end | :retry,
            to_id: any(),
            count: pos_integer(),
            conditions: list(Agens.Router.Condition.t())
          }

    defstruct type: :route, to_id: nil, count: 1, conditions: []
  end

  @impl Agens.Router
  def outputs(%Message{job_id: job_id}) do
    Application.get_env(:agens_demo, {:job_outputs, job_id}, [])
  end

  @impl Agens.Router
  def resolve(message, outputs) do
    all_edges = edges(message)

    all_edges
    |> Enum.filter(&(&1.type != :fallback))
    |> Enum.filter(fn edge ->
      Enum.all?(edge.conditions, &Condition.check(&1, outputs))
    end)
    |> maybe_fallback(all_edges)
    |> Enum.map(&to_next/1)
  end

  defp edges(%Message{job_id: job_id, node_id: node_id}) do
    :agens_demo
    |> Application.get_env({:job_edges, job_id}, %{})
    |> Map.get(node_id, [%Edge{type: :end}])
  end

  defp maybe_fallback([], edges), do: Enum.filter(edges, &(&1.type == :fallback))
  defp maybe_fallback(matched, _), do: matched

  defp to_next(%Edge{type: type, to_id: to_id, count: count}) when type in [:route, :fallback],
    do: {:route, to_id, count}

  defp to_next(%Edge{type: :yield, to_id: to_id}), do: {:yield, to_id}
  defp to_next(%Edge{type: :end}), do: :end
  defp to_next(%Edge{type: :retry}), do: :retry
end
