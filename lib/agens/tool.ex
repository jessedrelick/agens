defmodule Agens.Tool do
  @doc """
  Pre-process the input from previous Step before it is added to the LM prompt.
  """
  @callback pre(input :: String.t()) :: String.t()

  @doc """
  Instructions for the LM, combined with the input from previous Step (and optionally pre-processed using `pre/1`) as well as the prompt from the Agent config.
  """
  @callback instructions() :: String.t()

  @doc """
  Parse the LM result into arguments to be used by `execute/1`.
  """
  @callback to_args(result :: binary()) :: keyword()

  @doc """
  Execute the tool with the given arguments. LM is responsible for generating arguments for the Tool based on Tool instructions, input from previous Step, Agent config and any additional context.
  """
  @callback execute(args :: keyword()) :: map() | {:error, atom()}

  @doc """
  Handles the various outputs of `execute/1`, whether a map or error tuple, and returns a string for the next Step of the Job.
  """
  @callback post(map() | {:error, atom()}) :: String.t()
end
