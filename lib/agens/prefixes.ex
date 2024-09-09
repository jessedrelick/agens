defmodule Agens.Prefixes do
  @moduledoc """
  The Prefixes struct represents configurable prompt prefixes used in Agens.
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
