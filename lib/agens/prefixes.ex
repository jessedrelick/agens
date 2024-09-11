defmodule Agens.Prefixes do
  @moduledoc """
  The Prefixes struct is used to configure prompt prefixes for building advanced prompts.

  For each field used in the prompt (based on the configuration of Agents, Servings, and Jobs), a `heading` will be added, as well as some additional `detail`.

  For example, if you are running an `Agens.Job` and have defined an `objective` for the current `Agens.Job.Step`, the following will be added to the prompt:

  ```markdown
  ## Step Objective

  The objective of this step is to {{step.objective}}
  ```

  However, if you have not defined an `objective` for the current `Agens.Job.Step`, the `heading` and `detail` will also be omitted.

  Default prompt prefixes can be overridden globally with the `prefixes` option in `Agens.Supervisor`, or for individual servings with `Agens.Serving.Config`.

  See the [Prompting](README.md#prompting) section in the README for more information.
  """

  @type pair :: {heading :: String.t(), detail :: String.t()}
  @type t :: %__MODULE__{
          prompt: pair(),
          identity: pair(),
          context: pair(),
          constraints: pair(),
          examples: pair(),
          reflection: pair(),
          instructions: pair(),
          objective: pair(),
          description: pair(),
          input: pair()
        }

  @enforce_keys [
    :prompt,
    :identity,
    :context,
    :constraints,
    :examples,
    :reflection,
    :instructions,
    :objective,
    :description,
    :input
  ]
  defstruct [
    :prompt,
    :identity,
    :context,
    :constraints,
    :examples,
    :reflection,
    :instructions,
    :objective,
    :description,
    :input
  ]

  @doc false
  @spec default() :: t
  def default() do
    %__MODULE__{
      prompt:
        {"Agent", "You are a specialized agent with the following capabilities and expertise"},
      identity:
        {"Identity", "You are a specialized agent with the following capabilities and expertise"},
      context: {"Context", "The purpose or goal behind your tasks are to"},
      constraints:
        {"Constraints", "You must operate with the following constraints or limitations"},
      examples:
        {"Examples", "You should consider the following examples before returning results"},
      reflection:
        {"Reflection", "You should reflect on the following factors before returning results"},
      instructions:
        {"Tool Instructions",
         "You should provide structured output for function calling based on the following instructions"},
      objective: {"Step Objective", "The objective of this step is to"},
      description: {"Job Description", "This is part of multi-step job to achieve the following"},
      input: {"Input", "The following is the actual input from the user, system or another agent"}
    }
  end
end
