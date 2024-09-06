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
  - `Agens.Message` - used to facilitate communication between agents, jobs, and servings
  """

  defmodule Prefixes do
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
          {"Identity",
           "You are a specialized agent with the following capabilities and expertise"},
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
        description:
          {"Job Description", "This is part of multi-step job to achieve the following"},
        input:
          {"Input", "The following is the actual input from the user, system or another agent"}
      }
    end
  end

  use DynamicSupervisor

  @doc false
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :supervisor
    }
  end

  @doc false
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(args) do
    opts = Keyword.fetch!(args, :opts)
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(opts) do
    DynamicSupervisor.init(strategy: :one_for_one, extra_arguments: [opts])
  end

  @doc false
  @spec name_to_pid(atom(), {:error, term()}, (pid() -> any())) :: any()
  def name_to_pid(name, err, cb) do
    case Process.whereis(name) do
      nil -> err
      pid when is_pid(pid) -> cb.(pid)
    end
  end
end
