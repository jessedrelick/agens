defmodule Agens.Prompt do
  @moduledoc """
  Builds the system/user prompt pairs for a `Agens.Message` prior to LM inference.

  `build/3` assembles the structured fields of a `Agens.Message` (objective, description, input,
  previous result, resources, tool definitions/calls/results, retry reason, optional context)
  into two lists of `{prefix, value}` pairs - one for the system prompt and one for the user prompt.
  Each pair pairs a header/detail tuple from `Agens.Prefixes` with the corresponding value.

  Empty values are filtered out so that omitted fields produce no prompt section. Servings can
  override the default prefixes via `Agens.Serving.Config` or `Agens.Supervisor` options.

  This module is part of the internal prompt pipeline; servings normally call it indirectly through
  the default `build_prompt/3` implementation injected by `use Agens.Serving`.
  """

  alias Agens.{Message, Prefixes}

  @system_keys ~w(description objective context tool_defs resources)a
  @user_keys ~w(input previous_result tool_calls tool_results retry)a
  @default_retry_reason "The previous response did not pass validation. Please review and try again."

  @doc false
  @spec build(Message.t(), Prefixes.t(), binary() | nil) :: {list(), list()}
  def build(%Message{} = message, prefixes, context) do
    pairs =
      %{
        objective: message.node_objective,
        description: message.job_description,
        input: message.input
      }
      |> maybe_add_context(context)
      |> maybe_add_previous_result(message.previous_result)
      |> maybe_add_resources(message.resources)
      |> maybe_add_tool_defs(message.tool_defs)
      |> maybe_add_tool_calls(message.tool_calls)
      |> maybe_add_tool_results(message.tool_results)
      |> maybe_add_retry(message.retries, message.retry_reason)
      |> Enum.reject(&filter_empty/1)

    system =
      pairs
      |> Enum.filter(fn {k, _} -> k in @system_keys end)
      |> Enum.map(fn {key, value} -> {Map.get(prefixes, key), value} end)

    user =
      pairs
      |> Enum.filter(fn {k, _} -> k in @user_keys end)
      |> Enum.map(fn {key, value} -> {Map.get(prefixes, key), value} end)

    {system, user}
  end

  @doc false
  @spec filter_empty({atom(), String.t()}) :: boolean()
  defp filter_empty({_, value}), do: value == "" or is_nil(value)

  @doc false
  @spec maybe_add_context(map(), String.t() | nil) :: map()
  defp maybe_add_context(map, nil), do: map

  defp maybe_add_context(map, context) when is_binary(context),
    do: Map.put(map, :context, context)

  @doc false
  defp maybe_add_previous_result(map, nil), do: map

  defp maybe_add_previous_result(map, previous_result) when is_binary(previous_result),
    do: Map.put(map, :previous_result, previous_result)

  @doc false
  defp maybe_add_resources(map, resources) when is_list(resources) and length(resources) > 0 do
    content =
      resources
      |> Enum.filter(&(&1.content != nil))
      |> Enum.map_join("\n\n", fn r -> "### #{r.uri}\n\n```\n#{r.content}\n```" end)

    if content != "", do: Map.put(map, :resources, content), else: map
  end

  defp maybe_add_resources(map, _), do: map

  @doc false
  defp maybe_add_tool_defs(map, defs) when is_list(defs) and length(defs) > 0 do
    Map.put(map, :tool_defs, defs)
  end

  defp maybe_add_tool_defs(map, _), do: map

  @doc false
  defp maybe_add_tool_calls(map, calls) when is_list(calls) and length(calls) > 0 do
    Map.put(map, :tool_calls, calls)
  end

  defp maybe_add_tool_calls(map, _), do: map

  @doc false
  defp maybe_add_tool_results(map, results) when is_map(results) do
    Map.put(map, :tool_results, results)
  end

  defp maybe_add_tool_results(map, _), do: map

  @doc false
  @spec maybe_add_retry(map(), integer(), String.t() | nil) :: map()
  defp maybe_add_retry(map, retries, retry_reason) when is_integer(retries) and retries > 0 do
    reason = if retry_reason not in [nil, ""], do: retry_reason, else: @default_retry_reason

    Map.put(map, :retry, reason)
  end

  defp maybe_add_retry(map, _retries, _retry_reason), do: map
end
