defmodule Agens.Router.Output do
  @type t :: %__MODULE__{
          key: String.t(),
          type: String.t(),
          description: String.t(),
          values: list(String.t()) | nil,
          meta: map() | nil,
          value: any()
        }

  defstruct [:key, :type, :description, :values, :meta, :value]

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
      "enum" => output.values || []
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
