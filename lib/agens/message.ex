defmodule Agens.Message do
  @moduledoc """
  The Message struct defines the details of a message passed between Agents, Jobs and Servings.

  ## Fields

    * `:parent_pid` - The process identifier of the parent/caller process.
    * `:input` - The input string for the message.
    * `:prompt` - The prompt string or `Agens.Agent.Prompt` struct for the message.
    * `:result` - The result string for the message.
    * `:agent_name` - The name of the `Agens.Agent`.
    * `:serving_name` - The name of the `Agens.Serving`.
    * `:job_name` - The name of the `Agens.Job`.
    * `:job_description` - The description of the `Agens.Job` to be added to the LM prompt.
    * `:step_index` - The index of the `Agens.Job.Step`.
    * `:step_objective` - The objective of the `Agens.Job.Step` to be added to the LM prompt.
  """

  @type t :: %__MODULE__{
          parent_pid: pid() | nil,
          input: String.t() | nil,
          prompt: String.t() | Agens.Agent.Prompt.t() | nil,
          result: String.t() | nil,
          agent_name: atom() | nil,
          serving_name: atom() | nil,
          job_name: atom() | nil,
          job_description: String.t() | nil,
          step_index: non_neg_integer() | nil,
          step_objective: String.t() | nil
        }

  @enforce_keys []
  defstruct [
    :parent_pid,
    :input,
    :prompt,
    :result,
    :agent_name,
    :serving_name,
    :job_name,
    :job_description,
    :step_index,
    :step_objective
  ]

  alias Agens.{Agent, Serving}

  @doc """
  Sends an `Agens.Message` to an `Agens.Agent`
  """
  @spec send(__MODULE__.t()) :: __MODULE__.t() | {:error, atom()}
  def send(%__MODULE__{agent_name: nil, serving_name: nil}) do
    {:error, :no_agent_or_serving_name}
  end

  def send(%__MODULE__{} = message) do
    with {:ok, agent_config} <- maybe_get_agent_config(message.agent_name),
         {:ok, serving_config} <- get_serving_config(agent_config, message) do
      base = build_prompt(agent_config, message, serving_config.prompts)
      prompt = "<s>[INST]#{base}[/INST]"

      message =
        message
        |> Map.put(:prompt, prompt)
        |> Map.put(:serving_name, serving_config.name)

      result = Serving.run(message)

      message = Map.put(message, :result, result)
      tool = if agent_config, do: agent_config.tool, else: nil
      maybe_use_tool(message, tool)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec build_prompt(Agent.Config.t() | nil, t(), map()) :: String.t()
  defp build_prompt(nil, %__MODULE__{} = message, prompts) do
    %{
      objective: message.step_objective,
      description: message.job_description
    }
    |> Enum.reject(&filter_empty/1)
    |> Enum.map(fn {key, value} -> field({key, value}, prompts) end)
    |> Enum.map(&to_prompt/1)
    |> Enum.join("\n\n")
  end

  defp build_prompt(%Agent.Config{prompt: prompt, tool: tool}, %__MODULE__{} = message, prompts) do
    %{
      objective: message.step_objective,
      description: message.job_description
    }
    |> maybe_add_prompt(prompt)
    |> maybe_add_tool(tool)
    |> maybe_prep_input(message.input, tool)
    |> Enum.reject(&filter_empty/1)
    |> Enum.map(fn {key, value} -> field({key, value}, prompts) end)
    |> Enum.map(&to_prompt/1)
    |> Enum.join("\n\n")
  end

  defp filter_empty({_, value}), do: value == "" or is_nil(value)

  defp field({key, value}, prompts) do
    {Map.get(prompts, key), value}
  end

  defp to_prompt({{heading, detail}, value}) do
    """
    ## #{heading}
    #{detail}: #{value}
    """
  end

  defp maybe_add_prompt(map, %Agent.Prompt{} = prompt),
    do: prompt |> Map.from_struct() |> Map.merge(map)

  defp maybe_add_prompt(map, prompt) when is_binary(prompt), do: Map.put(map, :prompt, prompt)
  defp maybe_add_prompt(map, _prompt), do: map

  defp maybe_add_tool(map, nil), do: map
  defp maybe_add_tool(map, tool), do: Map.put(map, :instructions, tool.instructions())

  defp maybe_prep_input(map, input, nil), do: Map.put(map, :input, input)
  defp maybe_prep_input(map, input, tool), do: Map.put(map, :input, tool.pre(input))

  @spec maybe_use_tool(__MODULE__.t(), module() | nil) :: __MODULE__.t()
  defp maybe_use_tool(message, nil), do: message

  defp maybe_use_tool(%__MODULE__{} = message, tool) do
    send(
      message.parent_pid,
      {:tool_started, {message.job_name, message.step_index}, message.result}
    )

    raw =
      message.result
      |> tool.to_args()
      |> tool.execute()

    send(message.parent_pid, {:tool_raw, {message.job_name, message.step_index}, raw})

    result = tool.post(raw)

    send(message.parent_pid, {:tool_result, {message.job_name, message.step_index}, result})

    Map.put(message, :result, result)
  end

  defp get_serving_config(nil, %__MODULE__{serving_name: serving_name}) when is_atom(serving_name), do: Serving.get_config(serving_name)
  defp get_serving_config(%Agent.Config{serving: serving_name}, _) when is_atom(serving_name), do: Serving.get_config(serving_name)
  defp get_serving_config(_, _), do: {:error, :no_serving_name}

  defp maybe_get_agent_config(nil), do: {:ok, nil}
  defp maybe_get_agent_config(agent_name) when is_atom(agent_name), do: Agent.get_config(agent_name)
end
