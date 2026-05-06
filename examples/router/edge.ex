defmodule AgensRouter.Edge do
  alias Agens.Router.Condition

  @type t :: %__MODULE__{
          type: :route | :fallback | :yield | :end | :retry,
          to_id: any(),
          count: pos_integer(),
          conditions: list(Agens.Router.Condition.t())
        }

  defstruct type: :route, to_id: nil, count: 1, conditions: []

  @spec get(list(t()), list(Agens.Router.Output.t())) :: list()
  def get(edges, outputs) do
    edges
    |> Enum.filter(&(&1.type != :fallback))
    |> Enum.filter(fn edge ->
      Enum.all?(edge.conditions, &Condition.check(&1, outputs))
    end)
    |> maybe_use_fallback(edges)
    |> Enum.map(&to_next/1)
  end

  defp maybe_use_fallback([], edges), do: Enum.filter(edges, &(&1.type == :fallback))
  defp maybe_use_fallback(matched, _), do: matched

  defp to_next(%__MODULE__{type: type, to_id: to_id, count: count}) when type in [:route, :fallback],
    do: {:route, to_id, count}

  defp to_next(%__MODULE__{type: :yield, to_id: to_id}), do: {:yield, to_id}
  defp to_next(%__MODULE__{type: :end}), do: :end
  defp to_next(%__MODULE__{type: :retry}), do: :retry
end
