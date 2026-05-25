defmodule Agens.Router.Output do
  @moduledoc """
  Declares a single structured output field that a Router expects from a Serving.

  An `Agens.Router.Output` describes both the schema of a structured output key
  (used to build the LM-facing JSON Schema via `to_json_schema/1`) and, at runtime,
  the resolved value supplied by the Serving (`:value`).

  ## Fields

    * `:key` - The output key name. Must match a property in the Serving's structured response.
    * `:type` - One of `"int"`, `"enum"`, `"bool"`, or `"string"`.
    * `:description` - Human-readable description rendered into the JSON Schema.
    * `:meta` - Optional per-type constraint map. For `"int"`, supports `:min` and `:max`.
      For `"enum"`, supports `:choices` (the allowed string values).
    * `:value` - The resolved value at runtime; `nil` until populated from the Serving response.
  """

  @type t :: %__MODULE__{
          key: String.t(),
          type: String.t(),
          description: String.t(),
          meta: map() | nil,
          value: any()
        }

  defstruct [:key, :type, :description, :meta, :value]

  @doc """
  Converts a list of `Agens.Router.Output` declarations into a JSON Schema `properties` map.

  Each output is mapped to a typed JSON Schema fragment. Per-type constraints are read from
  `:meta`: `"int"` honors `:min`/`:max`; `"enum"` honors `:choices`. The returned map is
  suitable for use as the `outputs` property in a Serving's structured response schema.
  """
  @spec to_json_schema(list(t())) :: map()
  def to_json_schema(outputs) when is_list(outputs) do
    Map.new(outputs, fn %__MODULE__{key: key} = output ->
      {key, to_json_field(output)}
    end)
  end

  defp to_json_field(%__MODULE__{type: "int"} = output) do
    %{
      "type" => "integer",
      "description" => output.description,
      "title" => "outputs.#{output.key}"
    }
    |> maybe_put("minimum", output.meta && output.meta[:min])
    |> maybe_put("maximum", output.meta && output.meta[:max])
  end

  defp to_json_field(%__MODULE__{type: "enum"} = output) do
    %{
      "type" => "string",
      "description" => output.description,
      "title" => "outputs.#{output.key}",
      "enum" => (output.meta && output.meta[:choices]) || []
    }
  end

  defp to_json_field(%__MODULE__{type: "bool"} = output) do
    %{
      "type" => "boolean",
      "description" => output.description,
      "title" => "outputs.#{output.key}"
    }
  end

  defp to_json_field(%__MODULE__{type: "string"} = output) do
    %{"type" => "string", "description" => output.description, "title" => "outputs.#{output.key}"}
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
