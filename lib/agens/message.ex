defmodule Agens.Message do
  @moduledoc """
  The Message struct defines the details of a message passed between Agents, Jobs and Servings.

  ## Fields

    * `:parent_pid` - The process identifier of the parent/caller process.
    * `:input` - The input string for the message. Required.
    * `:prompt` - The final prompt string constructed for `Agens.Serving.run/1`.
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
          input: String.t(),
          prompt: String.t() | Agens.Agent.Prompt.t() | nil,
          result: String.t() | nil,
          agent_name: atom() | nil,
          serving_name: atom() | nil,
          job_name: atom() | nil,
          job_description: String.t() | nil,
          step_index: non_neg_integer() | nil,
          step_objective: String.t() | nil
        }

  @enforce_keys [:input]
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

  alias Agens.{Agent, Prefixes, Serving}

  @doc """
  Sends an `Agens.Message` to an `Agens.Agent` or `Agens.Serving`.
  """
  @spec send(t()) :: t() | {:error, atom()}
  def send(%__MODULE__{input: input}) when input in ["", nil] do
    {:error, :input_required}
  end

  def send(%__MODULE__{agent_name: nil, serving_name: nil}) do
    {:error, :no_agent_or_serving_name}
  end

  def send(%__MODULE__{} = message) do
    with {:ok, agent_config} <- maybe_get_agent_config(message.agent_name),
         {:ok, serving_config} <- get_serving_config(agent_config, message),
         base <- build_prompt(agent_config, message, serving_config.prefixes),
         {:ok, prompt} <- Serving.finalize(serving_config.name, base) do
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

  @doc false
  @spec build_prompt(Agent.Config.t() | nil, t(), Prefixes.t()) :: String.t()
  defp build_prompt(agent_config, %__MODULE__{} = message, prefixes) do
    %{
      objective: message.step_objective,
      description: message.job_description
    }
    |> maybe_add_prompt(agent_config)
    |> maybe_add_tool(agent_config)
    |> maybe_prep_input(message.input, agent_config)
    |> Enum.reject(&filter_empty/1)
    |> Enum.map(fn {key, value} -> field({key, value}, prefixes) end)
    |> Enum.map(&to_prompt/1)
    |> Enum.join("\n\n")
  end

  @doc false
  @spec filter_empty({atom(), String.t()}) :: boolean()
  defp filter_empty({_, value}), do: value == "" or is_nil(value)

  @doc false
  @spec field({atom(), String.t()}, Prefixes.t()) :: {String.t(), String.t()}
  defp field({key, value}, prefixes) do
    {Map.get(prefixes, key), value}
  end

  @doc false
  @spec to_prompt({{String.t(), String.t()}, String.t()}) :: String.t()
  defp to_prompt({{heading, detail}, value}) do
    """
    ## #{heading}
    #{detail}: #{value}
    """
  end

  @doc false
  @spec maybe_add_prompt(map(), Agent.Config.t() | nil) :: map()
  defp maybe_add_prompt(map, %Agent.Config{prompt: %Agent.Prompt{} = prompt}),
    do: prompt |> Map.from_struct() |> Map.merge(map)

  defp maybe_add_prompt(map, %Agent.Config{prompt: prompt}) when is_binary(prompt),
    do: Map.put(map, :prompt, prompt)

  defp maybe_add_prompt(map, _), do: map

  @doc false
  @spec maybe_add_tool(map(), Agent.Config.t() | nil) :: map()
  defp maybe_add_tool(map, %Agent.Config{tool: tool}) when not is_nil(tool),
    do: Map.put(map, :instructions, tool.instructions())

  defp maybe_add_tool(map, _), do: map

  @doc false
  @spec maybe_prep_input(map(), String.t(), Agent.Config.t() | nil) :: map()
  defp maybe_prep_input(map, input, %Agent.Config{tool: tool}) when not is_nil(tool),
    do: Map.put(map, :input, tool.pre(input))

  defp maybe_prep_input(map, input, _), do: Map.put(map, :input, input)

  @doc false
  @spec maybe_use_tool(t(), module() | nil) :: t()
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

  @doc false
  @spec get_serving_config(Agent.Config.t() | nil, t()) ::
          {:ok, Serving.Config.t()} | {:error, atom()}
  defp get_serving_config(nil, %__MODULE__{serving_name: serving_name})
       when is_atom(serving_name),
       do: Serving.get_config(serving_name)

  defp get_serving_config(%Agent.Config{serving: serving_name}, _) when is_atom(serving_name),
    do: Serving.get_config(serving_name)

  @doc false
  @spec maybe_get_agent_config(atom() | nil) :: {:ok, Agent.Config.t() | nil}
  defp maybe_get_agent_config(nil), do: {:ok, nil}

  defp maybe_get_agent_config(agent_name) when is_atom(agent_name),
    do: Agent.get_config(agent_name)
end
