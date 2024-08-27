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

    @doc """
    Sends an `Agens.Message` to an `Agens.Agent`
    """
    @spec send(__MODULE__.t()) :: __MODULE__.t() | {:error, atom()}
    def send(%__MODULE__{agent_name: nil, serving_name: nil}) do
      {:error, :no_agent_or_serving_name}
    end

    def send(%__MODULE__{serving_name: nil} = message) do
      case Agent.get_config(message.agent_name) do
        %Agent.Config{serving: serving} ->
          message
          |> Map.put(:serving_name, serving)
          |> Serving.run()

        {:error, reason} ->
          {:error, reason}
      end
    end

    def send(%__MODULE__{} = message) do
      Serving.run(message)
    end

    @spec build_prompt(Agent.Config.t() | nil, t(), map()) :: String.t()
    def build_prompt(nil, %__MODULE__{} = message, prompts) do
      %{
        objective: message.step_objective,
        description: message.job_description
      }
      |> Enum.reject(&filter_empty/1)
      |> Enum.map(fn {key, value} -> field({key, value}, prompts) end)
      |> Enum.map(&to_prompt/1)
      |> Enum.join("\n\n")
    end

    def build_prompt(%Agent.Config{prompt: prompt, tool: tool}, %__MODULE__{} = message, prompts) do
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
    def maybe_use_tool(message, nil), do: message

    def maybe_use_tool(%__MODULE__{} = message, tool) do
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
  @spec start_link(keyword()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    opts = Keyword.fetch!(args, :opts)
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @spec init(keyword()) :: {:ok, any()}
  def init(opts) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [opts])
  end
end
