defmodule Agens.Tool do
  @moduledoc """
  The Tool behaviour.

  A Tool is a module that implements the `Agens.Tool` behaviour. It is used to define
  the functionality of a tool that can be used by an `Agens.Agent`.

  A Tool defines the following callbacks:

    - `pre/1` - pre-processes the input from the previous step before it is added to the LM prompt.
    - `instructions/0` - returns the instructions for the LM, combined with the input from the previous step and the prompt from the Agent config.
    - `to_args/1` - parses the LM result into arguments to be used by `execute/1`.
    - `execute/1` - executes the tool with the given arguments.
    - `post/1` - handles the various outputs of `execute/1`, whether a map or error tuple, and returns a string for the next Step of the Job.
  """

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
