defmodule Agens.Router do
  @moduledoc """
  Behaviour and macro for routing a Node's result to the next instruction(s).

  A Router maps the `outputs` produced by a Serving onto a list of route instructions
  (e.g. `{:route, node_id, 1}`, `{:yield, node_id}`, `:end`, `:retry`). The Router can
  be implemented either:

    * **Merged** - in the Serving module itself by `use Agens.Router` alongside `use Agens.Serving`.
    * **Split** - in a dedicated module reused across Servings, passed via `use Agens.Serving, router: MyRouter`.

  ## Implementing a Router

  A Router must implement two callbacks:

    * `c:outputs/1` - declares the `Agens.Router.Output` schema for the Node's structured outputs.
    * `c:resolve/2` - maps a populated outputs list to a list of route instructions.

  Using `use Agens.Router` injects a `route/1` and `route/2` function that combine these:
  `route/1` validates the Serving's structured `outputs` against the declared schema and calls
  `resolve/2`. `route/2` accepts a dynamic LM-supplied `next` list and merges it via `parse_next/1`,
  falling back to `route/1` when the dynamic list resolves to no usable instructions.

  ## LM-driven dynamic routing

  When a Serving's structured response includes a non-empty `next` list, those entries are decoded
  by `parse_next/1` and used in place of the static Router's resolution.
  """

  alias Agens.Message

  @doc """
  Declares the `Agens.Router.Output` schema for a Node's structured outputs.

  The returned list is used both to validate the Serving's outputs (every declared key must
  be present) and as the input to `c:resolve/2`.
  """
  @callback outputs(Message.t()) :: list(Agens.Router.Output.t())

  @doc """
  Maps the populated `Agens.Router.Output` list onto a list of route instructions.
  """
  @callback resolve(Message.t(), list(Agens.Router.Output.t())) :: list()

  defmacro __using__(_opts) do
    quote do
      @behaviour Agens.Router

      alias Agens.Router.Output
      alias Agens.Message

      @doc """
      Routes a `Agens.Message` by validating its `outputs` against the declared
      `c:Agens.Router.outputs/1` schema and delegating to `c:Agens.Router.resolve/2`.

      Returns `[:retry]` if outputs are missing or invalid.
      """
      def route(%Message{} = message) do
        case prepare_outputs(message) do
          {:ok, merged} -> resolve(message, merged)
          {:error, _} -> [:retry]
        end
      end

      @doc """
      Routes a `Agens.Message` while honoring an LM-supplied dynamic `next` list.

      The dynamic list is decoded by `Agens.Router.parse_next/1`. When it yields any valid
      instructions, those are returned. Otherwise routing falls back to `route/1`.
      """
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

  @doc """
  Decodes an LM-supplied `next` list (a list of `%{"type" => ..., "value" => ...}` maps)
  into Agens route instructions.

  Unknown entries are dropped. Supported types: `"route"`, `"yield"`, `"sub"`, `"end"`, `"retry"`.
  """
  @spec parse_next(list(map())) :: list()
  def parse_next(next) when is_list(next) do
    next
    |> Enum.map(&do_parse/1)
    |> Enum.reject(&is_nil/1)
  end

  defp do_parse(%{"type" => "route", "value" => value}), do: {:route, value, 1}
  defp do_parse(%{"type" => "yield", "value" => value}), do: {:yield, value}
  defp do_parse(%{"type" => "sub", "value" => value}), do: {:sub, value}
  defp do_parse(%{"type" => "end"}), do: :end
  defp do_parse(%{"type" => "retry"}), do: :retry
  defp do_parse(_), do: nil
end
