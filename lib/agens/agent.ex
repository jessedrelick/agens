defmodule Agens.Agent do
  defstruct [:name, :serving, :context, :knowledge, :prompt, :tool]

  defmodule Prompt do
    @derive Jason.Encoder
    defstruct [:identity, :context, :constraints, :examples, :reflection, :input]
  end

  def base_prompt(%__MODULE__{prompt: %Prompt{} = prompt, tool: tool}, input) do
    """
    ## Identity
    You are a specialized agent with the following capabilities and expertise: #{prompt.identity}

    ## Context
    The purpose or goal behind your tasks are to: #{prompt.context}

    ## Constraints
    You must operate with the following constraints or limitations: #{prompt.constraints}

    ## Reflection
    You should consider the following factors before returning results: #{prompt.reflection}

    #{maybe_add_tool_instructions(tool)}

    ## Input
    The following is the actual input from the user, system or another agent: `#{input}`
    """
  end

  def base_prompt(%__MODULE__{prompt: prompt, tool: nil}, input),
    do: "Agent: #{prompt} Input: #{input}"

  def base_prompt(%__MODULE__{prompt: prompt, tool: tool}, input) when is_atom(tool),
    do: "Agent: #{prompt} Tool: #{tool.instructions()} Input: #{tool.pre(input)}"

  def maybe_use_tool(nil, text), do: text

  def maybe_use_tool(tool, text) do
    # send(parent, {:tool_started, {job_name, step_index}, text})

    raw =
      text
      |> tool.to_args()
      |> tool.execute()

    # send(parent, {:tool_raw, {job_name, step_index}, raw})

    tool.post(raw)

    # send(parent, {:tool_result, {job_name, step_index}, result})
  end

  defp maybe_add_tool_instructions(nil), do: ""

  defp maybe_add_tool_instructions(tool) when is_atom(tool) do
    """
    ## Tool Instructions
    #{tool.instructions()}
    """
  end
end
