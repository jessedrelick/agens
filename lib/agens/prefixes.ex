defmodule Agens.Prefixes do
  @moduledoc """
  The Prefixes struct is used to configure prompt prefixes for building advanced prompts.

  For each field used in the prompt (based on the configuration of Servings, Jobs, and their Nodes), a `heading` will be added, as well as some additional `detail`.

  For example, if you are running an `Agens.Job` and have defined an `objective` for the current `Agens.Job.Node`, the following will be added to the prompt:

  ```markdown
  ## Node Objective

  The objective of this node is to {{node.objective}}
  ```

  However, if you have not defined an `objective` for the current `Agens.Job.Node`, the `heading` and `detail` will also be omitted.

  Default prompt prefixes can be overridden globally with the `prefixes` option in `Agens.Supervisor`, or for individual servings with `Agens.Serving.Config`.

  See the [Prompting](README.md#prompting) section in the README for more information.
  """

  @type pair :: {heading :: String.t(), detail :: String.t()}
  @type t :: %__MODULE__{
          context: pair(),
          objective: pair(),
          description: pair(),
          input: pair(),
          previous_result: pair(),
          schema: pair(),
          retry: pair(),
          tool_defs: pair(),
          tool_calls: pair(),
          tool_results: pair(),
          resources: pair()
        }

  @enforce_keys [
    :context,
    :objective,
    :description,
    :input,
    :previous_result,
    :schema,
    :retry,
    :tool_defs,
    :tool_calls,
    :tool_results,
    :resources
  ]
  defstruct [
    :context,
    :objective,
    :description,
    :input,
    :previous_result,
    :schema,
    :retry,
    :tool_defs,
    :tool_calls,
    :tool_results,
    :resources
  ]

  @tool_defs """
  You have access to the following MCP tools. If you need to call one or more tools to complete \
  the task, populate the `tool_calls` field in your structured response. If tool results have \
  already been provided, use them to generate your response in `body` and `outputs` instead of \
  making additional tool calls. The available tools are:
  """

  @doc false
  @spec default() :: t
  def default() do
    %__MODULE__{
      context: {"Context", "The following is critical context relevant to this task"},
      objective: {"Node Objective", "The objective of this node is to"},
      description:
        {"Job Description", "This is part of a multi-node job to achieve the following"},
      input: {"Input", "The following is the original input from the user"},
      previous_result:
        {"Previous Result", "The following is the result from the previous node in this job"},
      schema:
        {"Schema",
         "It is critical to only return a JSON object matching the exact specification below"},
      retry:
        {"Retry",
         "The response did not pass validation. Please try again and fix the following validation errors"},
      tool_defs: {"Tool Definitions", @tool_defs},
      tool_calls: {"Tool Calls", "The following MCP tool calls were made by this node"},
      tool_results:
        {"Tool Results",
         "The following are the results of MCP tool calls for this node. Use these results to formulate your response in `body` and `outputs`"},
      resources: {"Resources", "The following resources are provided as context for this node"}
    }
  end
end
