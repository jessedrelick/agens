defmodule AgensRouter.Destination do
  alias AgensRouter.{Condition, Edge}

  @spec get(list(Edge.t()), list()) :: list()
  def get(edges, outputs) do
    edges
    |> Enum.filter(&(&1.type != :fallback))
    |> Enum.filter(fn edge ->
      Enum.all?(edge.conditions, &Condition.apply(&1, outputs))
    end)
    |> maybe_use_fallback(edges)
    |> Enum.map(&to_next/1)
  end

  defp maybe_use_fallback([], edges), do: Enum.filter(edges, &(&1.type == :fallback))
  defp maybe_use_fallback(matched, _), do: matched

  defp to_next(%Edge{type: type, to_id: to_id, count: count}) when type in [:route, :fallback],
    do: {:route, to_id, count}

  defp to_next(%Edge{type: :yield, to_id: to_id}), do: {:yield, to_id}
  defp to_next(%Edge{type: :end}), do: :end
  defp to_next(%Edge{type: :retry}), do: :retry
end
