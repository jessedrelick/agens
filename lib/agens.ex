# Copyright 2024 Jesse Drelick
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

defmodule Agens do
  @moduledoc """
  Agens is used to create multi-agent workflows with language models.

  It is made up of the following core entities:

  - `Agens.Serving` - used to interact with language models
  - `Agens.Agent` - used to interact with servings in a specialized manner
  - `Agens.Job` - used to define multi-agent workflows
  """

  defmodule Message do
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

    @registry Application.compile_env(:agens, :registry)
    @fields Application.compile_env(:agens, :prompts, %{
              prompt:
                {"Agent",
                 "You are a specialized agent with the following capabilities and expertise"},
              identity:
                {"Identity",
                 "You are a specialized agent with the following capabilities and expertise"},
              context: {"Context", "The purpose or goal behind your tasks are to"},
              constraints:
                {"Constraints", "You must operate with the following constraints or limitations"},
              examples:
                {"Examples",
                 "You should consider the following examples before returning results"},
              reflection:
                {"Reflection",
                 "You should reflect on the following factors before returning results"},
              instructions:
                {"Tool Instructions",
                 "You should provide structured output for function calling based on the following instructions"},
              objective: {"Step Objective", "The objective of this step is to"},
              description:
                {"Job Description", "This is part of multi-step job to achieve the following"},
              input:
                {"Input",
                 "The following is the actual input from the user, system or another agent"}
            })

    @doc """
    Sends an `Agens.Message` to an `Agens.Agent`
    """
    @spec send(__MODULE__.t()) :: __MODULE__.t() | {:error, :agent_not_running}
    def send(%__MODULE__{} = message) do
      case Registry.lookup(@registry, message.agent_name) do
        [{_, {agent_pid, config}}] when is_pid(agent_pid) ->
          base = build_prompt(config, message)
          prompt = "<s>[INST]#{base}[/INST]"

          result =
            message
            |> Map.put(:serving_name, config.serving)
            |> Map.put(:prompt, prompt)
            |> Serving.run()

          message = Map.put(message, :result, result)
          maybe_use_tool(message, config.tool)

        [] ->
          {:error, :agent_not_running}
      end
    end

    @spec build_prompt(Agent.Config.t(), t()) :: String.t()
    defp build_prompt(%Agent.Config{prompt: prompt, tool: tool}, %__MODULE__{} = message) do
      %{
        objective: message.step_objective,
        description: message.job_description
      }
      |> maybe_add_prompt(prompt)
      |> maybe_add_tool(tool)
      |> maybe_prep_input(message.input, tool)
      |> Enum.reject(&filter_empty/1)
      |> Enum.map(&field/1)
      |> Enum.map(&to_prompt/1)
      |> Enum.join("\n\n")
    end

    defp filter_empty({_, value}), do: value == "" or is_nil(value)

    defp field({key, value}) do
      {Map.get(@fields, key), value}
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
  end

  use DynamicSupervisor

  @doc false
  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc false
  @spec init(any()) :: {:ok, any()}
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
