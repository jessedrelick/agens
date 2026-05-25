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

  Default prefixes are returned by `default/0`. To customize, build an `%Agens.Prefixes{}` struct and set it on the `:prefixes` field of `Agens.Serving.Config`. To share custom prefixes across many Servings, define a module that returns the struct and reference it from each Serving's Config.

  ## Fields and Sources

  Each field maps a prompt section to a value sourced from the running `Agens.Message`. Fields with `nil`/empty values are omitted from the final prompt entirely.

  | Field             | Source                                                                                  |
  | ----------------- | --------------------------------------------------------------------------------------- |
  | `context`         | `c:Agens.Serving.load_context/2` (derived from `agent_id`)                    |
  | `objective`       | `Agens.Job.Node.objective`                                                              |
  | `description`     | `Agens.Job.Config.description`                                                          |
  | `input`           | The original value passed to `Agens.Job.run/3` (never overwritten across Nodes)         |
  | `previous_result` | The `result` of the previous Node in the Job (`nil` on the starting Node)               |
  | `schema`          | JSON schema built from the Router's declared `outputs/1` (plus response/tool-call shape)|
  | `retry`           | Validation/retry reason when re-running a Node                                          |
  | `tool_defs`       | `Agens.Job.Node.tools` (MCP-style tool schemas)                                         |
  | `tool_calls`      | Tool call requests emitted by the LM in the previous turn                               |
  | `tool_results`    | Resolved tool-call results merged back from `c:Agens.Serving.tool_call/3`               |
  | `resources`       | Loaded `Agens.Resource` content (from `c:Agens.Serving.load_resource/3`)                |

  > **Note:**
  >
  > Depending on your use case, some fields may be more relevant than others. It's often beneficial to be more descriptive at granular levels (Node `objective`, Router `outputs`) while taking a more minimal approach at higher levels (Job `description`).
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

  @doc """
  Returns the default `Agens.Prefixes` struct used when a Serving's `Agens.Serving.Config.prefixes` is `nil`.

  Customize by building your own struct (typically starting from this default and overriding select fields) and setting it on the relevant `Agens.Serving.Config`.
  """
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
