defmodule Agens.Router.Condition do
  @moduledoc """
  A boolean comparison against a structured Router output value.

  Conditions are typically used by a Router's `c:Agens.Router.resolve/2` implementation
  to branch on the structured outputs produced by a Serving. The `:value` declared on
  the condition is coerced to the output's `:type` before comparison.

  ## Fields

    * `:key` - The `Agens.Router.Output` key to inspect.
    * `:op` - One of `"eq"`, `"neq"`, `"gt"`, `"lt"`, `"gte"`, `"lte"`.
    * `:value` - The literal value to compare against (as a string; coerced based on the output's type).
  """

  alias Agens.Router.Output

  @type t :: %__MODULE__{
          key: String.t(),
          op: String.t(),
          value: String.t() | nil
        }

  defstruct [:key, :op, :value]

  @doc """
  Evaluates the condition against a list of `Agens.Router.Output` values.

  Returns `false` if the key is missing or the resolved value is `nil`.
  Otherwise compares using the condition's `:op` after coercing the condition's
  `:value` to match the output's declared type.
  """
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
