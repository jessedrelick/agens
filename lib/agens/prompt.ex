defmodule Agens.Prompt do
  @moduledoc """
  Builds the system/user prompt pairs for a `Agens.Message` prior to LM inference.

  `build/3` assembles the structured fields of a `Agens.Message` (objective, description, input,
  previous result, resources, tool definitions/calls/results, retry reason, optional context)
  into two lists of `{prefix, value}` pairs - one for the system prompt and one for the user prompt.
  Each pair combines a header/detail tuple from `Agens.Prefixes` with the corresponding value.

  Empty values are filtered out so that omitted fields produce no prompt section. The goal is to
  balance detail with token usage by populating only the fields that matter for a given Node — a
  Node without tools won't carry a `Tool Definitions` section, a Node without an `objective` won't
  carry a `Node Objective` section, and so on.

  ## System vs User

  Fields are partitioned between the system prompt and the user prompt:

    * **System** — `description`, `objective`, `context`, `tool_defs`, `resources`. Stable,
      workflow-defining context that doesn't change across retries of the same Node.
    * **User** — `input`, `previous_result`, `tool_calls`, `tool_results`, `retry`. Per-turn data
      that varies between Nodes and across retries.

  Each section is rendered with the corresponding prefix's `heading` and `detail` from
  `Agens.Prefixes`.

  ## Pipeline

  For each request, `Agens.Serving` orchestrates roughly:

    1. Resolve any agent-specific context via `c:Agens.Serving.load_context/2`.
    2. Resolve `c:Agens.Serving.load_resource/3` for every `Agens.Resource` declared on the Node.
    3. Build the JSON schema from the Router's declared outputs (via `Agens.Router.Output.to_json_schema/1`).
    4. Stitch the prompt with `Agens.Prompt.build/3`, applying the Serving's prefixes.
    5. Send to the LM via `c:Agens.Serving.handle_message/3`.
    6. Parse the structured response and route via the Router.

  This module is part of the internal prompt pipeline; Servings normally call it indirectly via the
  default `c:Agens.Serving.build_prompt/3` injected by `use Agens.Serving`. Override `build_prompt/3`
  when you need full control over prompt construction (for example, emitting a chat-message format
  instead of system/user concatenation), or override `Agens.Serving.Config.prefixes` when you only
  need to customize the headings/detail of the existing sections.
  """

  alias Agens.{Message, Prefixes}

  @system_keys ~w(description objective context tool_defs resources)a
  @user_keys ~w(input previous_result tool_calls tool_results retry)a
  @default_retry_reason "The previous response did not pass validation. Please review and try again."

  @doc """
  Builds the system and user prompt pair for a `Agens.Message`.

  Returns `{system, user}` where each is a list of `{{heading, detail}, value}` tuples — the
  `heading`/`detail` come from the supplied `prefixes` and `value` comes from the corresponding
  field on the message. Servings render these pairs into final strings (the default
  `c:Agens.Serving.build_prompt/3` joins each tuple as `## heading\\ndetail:\\n\\nvalue`).

  Fields with `nil` or empty values are filtered out — a Node without an `:objective` won't carry
  a `Node Objective` section, a Node without `:tools` won't carry `Tool Definitions`, and so on.
  See the moduledoc for the full system-vs-user partition.

  ## Parameters

    * `message` - The `Agens.Message` whose fields drive the prompt sections.
    * `prefixes` - The `Agens.Prefixes` struct supplying `{heading, detail}` tuples for each
      section. Typically the Serving's `Agens.Serving.Config.prefixes`.
    * `context` - Optional string from `c:Agens.Serving.load_context/2`. When non-nil, surfaced
      under the `Context` prefix in the system prompt; when nil, the section is omitted.

  Retries with no explicit `retry_reason` fall back to a generic validation-failure message under
  the `Retry` prefix.
  """
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
