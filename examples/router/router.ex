defmodule AgensRouter do
  alias Agens.Message

  @callback outputs(Message.t()) :: list(AgensRouter.Output.t())
  @callback edges(Message.t()) :: list(AgensRouter.Edge.t())

  defmacro __using__(_opts) do
    quote do
      @behaviour AgensRouter

      alias AgensRouter.{Output, Destination}
      alias Agens.Message

      def route(%Message{next: next}) when is_list(next) and length(next) > 0, do: next

      def route(%Message{outputs: outputs_result} = message) do
        node_edges = edges(message)
        has_conditions? = Enum.any?(node_edges, fn e -> e.conditions != [] end)

        result =
          if has_conditions? do
            merge_outputs(outputs_result, outputs(message))
          else
            {:ok, []}
          end

        case result do
          {:error, _} -> [:retry]
          {:ok, merged} -> Destination.get(node_edges, merged)
        end
      end

      defp merge_outputs(outputs_result, outputs_def) when is_map(outputs_result) do
        merged =
          Enum.map(outputs_def, fn %Output{key: key} = config ->
            {key, %{value: Map.get(outputs_result, key), config: config}}
          end)

        if Enum.all?(outputs_def, fn %Output{key: k} -> Map.has_key?(outputs_result, k) end) do
          {:ok, merged}
        else
          {:error, :missing_output_keys}
        end
      end

      defp merge_outputs(_, _), do: {:error, :invalid_outputs}
    end
  end
end
