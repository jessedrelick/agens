defmodule Agens.Router do
  alias Agens.Message

  @callback outputs(Message.t()) :: list(Agens.Router.Output.t())
  @callback resolve(Message.t(), list(Agens.Router.Output.t())) :: list()

  defmacro __using__(_opts) do
    quote do
      @behaviour Agens.Router

      alias Agens.Router.Output
      alias Agens.Message

      def route(%Message{} = message) do
        case prepare_outputs(message) do
          {:ok, merged} -> resolve(message, merged)
          {:error, _} -> [:retry]
        end
      end

      def route(%Message{} = message, dynamic_next)
          when is_list(dynamic_next) and dynamic_next != [] do
        case Agens.Router.parse_next(dynamic_next) do
          [] -> route(message)
          next -> next
        end
      end

      def route(%Message{} = message, _), do: route(message)

      defp prepare_outputs(%Message{outputs: outputs_result} = message)
           when is_map(outputs_result) do
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

  @spec parse_next(list(map())) :: list()
  def parse_next(next) when is_list(next) do
    next
    |> Enum.map(&do_parse/1)
    |> Enum.reject(&is_nil/1)
  end

  defp do_parse(%{"type" => "route", "value" => value}), do: {:route, value, 1}
  defp do_parse(%{"type" => "yield", "value" => value}), do: {:yield, value}
  defp do_parse(%{"type" => "job", "value" => value}), do: {:job, value}
  defp do_parse(%{"type" => "end"}), do: :end
  defp do_parse(%{"type" => "retry"}), do: :retry
  defp do_parse(_), do: nil
end
