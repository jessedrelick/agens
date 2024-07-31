defmodule Agens.Agent do
  defstruct [:name, :serving, :context, :knowledge, :prompt]

  defmodule Prompt do
    @derive Jason.Encoder
    defstruct [:identity, :context, :constraints, :examples, :reflection]
  end

  def base_prompt(prompt, input) when is_binary(prompt), do: "#{prompt} Input: #{input}"

  def base_prompt(%Prompt{} = prompt, input) do
    """
    ## Identity
    You are a specialized agent with the following capabilities and expertise: #{prompt.identity}

    ## Context
    The purpose or goal behind your tasks are to: #{prompt.context}

    ## Constraints
    You must operate with the following constraints or limitations: #{prompt.constraints}

    ## Reflection
    You should consider the following factors before returning results: #{prompt.reflection}

    ## Input
    The following is the actual input from the user, system or another agent: `#{input}`
    """
  end
end
