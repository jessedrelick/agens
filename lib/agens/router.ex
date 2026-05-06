defmodule Agens.Router do
  alias Agens.Message

  @callback outputs(Message.t()) :: list(Agens.Router.Output.t())
  @callback resolve(Message.t(), list(Agens.Router.Output.t())) :: list()

  defmacro __using__(_opts) do
    quote do
      @behaviour Agens.Router

      alias Agens.Router.Output
      alias Agens.Message

      def route(%Message{next: next}) when is_list(next) and next != [], do: next

      def route(%Message{} = message) do
        case prepare_outputs(message) do
          {:ok, merged} -> resolve(message, merged)
          {:error, _} -> [:retry]
        end
      end

      defp prepare_outputs(%Message{outputs: outputs_result} = message) do
        outputs_def = outputs(message)

        if Enum.all?(outputs_def, fn %Output{key: k} -> Map.has_key?(outputs_result, k) end) do
          merged =
            Enum.map(outputs_def, fn %Output{key: key} = output ->
              %Output{output | value: Map.get(outputs_result, key)}
            end)

          {:ok, merged}
        else
          {:error, :missing_output_keys}
        end
      end

      defp prepare_outputs(_), do: {:error, :invalid_outputs}
    end
  end
end
