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
  @spec serving_pid(atom(), {:error, term()}, (pid() -> any())) :: any()
  def serving_pid(name, err, cb) do
    case Process.whereis(name) do
      nil -> err
      pid when is_pid(pid) -> cb.(pid)
    end
  end

  @doc false
  @spec job_pid(binary(), {:error, term()}, (pid() -> any())) :: any()
  def job_pid(job_id, err, cb) do
    case Registry.lookup(Agens.Registry, job_id) do
      [] -> err
      [{pid, _}] when is_pid(pid) -> cb.(pid)
    end
  end

  def backends(fun, args) when is_atom(fun) and is_list(args) do
    backends()
    |> Enum.map(&apply(&1, fun, args))
  end

  def backends() do
    Application.get_env(:agens, :backends, [Agens.Backend.Emit, Agens.Backend.Log])
  end
end
