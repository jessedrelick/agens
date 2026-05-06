defmodule Agens.Router.Condition do
  alias Agens.Router.Output

  @type t :: %__MODULE__{
          key: String.t(),
          op: String.t(),
          value: String.t() | nil
        }

  defstruct [:key, :op, :value]

  @spec check(t(), list(Output.t())) :: boolean()
  def check(%__MODULE__{key: key, op: op, value: condition_value}, outputs) do
    case Enum.find(outputs, fn %Output{key: k} -> k == key end) do
      nil ->
        false

      %Output{type: type, value: result_value} ->
        compare(result_value, op, coerce(type, condition_value))
    end
  end

  defp coerce(_, nil), do: nil
  defp coerce("int", v) when is_binary(v), do: String.to_integer(v)
  defp coerce("bool", "true"), do: true
  defp coerce("bool", _), do: false
  defp coerce(_, v), do: v

  defp compare(nil, _, _), do: false

  defp compare(result, op, condition) do
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
