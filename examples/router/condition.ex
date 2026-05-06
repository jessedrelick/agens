defmodule AgensRouter.Condition do
  @type t :: %__MODULE__{
          key: String.t(),
          op: String.t(),
          value: String.t() | nil
        }

  defstruct [:key, :op, :value]

  @spec apply(t(), list()) :: boolean()
  def apply(%__MODULE__{key: key, op: op, value: condition_value}, outputs) do
    case List.keyfind(outputs, key, 0) do
      nil ->
        false

      {_, %{config: config, value: result_value}} ->
        check(result_value, op, coerce(config.type, condition_value))
    end
  end

  defp coerce(_, nil), do: nil
  defp coerce("int", v) when is_binary(v), do: String.to_integer(v)
  defp coerce("bool", "true"), do: true
  defp coerce("bool", _), do: false
  defp coerce(_, v), do: v

  defp check(nil, _, _), do: false

  defp check(result, op, condition) do
    case op do
      "eq" -> result == condition
      "neq" -> result != condition
      "gt" -> result > condition
      "lt" -> result < condition
      "gte" -> result >= condition
      "lte" -> result <= condition
    end
  end
end
