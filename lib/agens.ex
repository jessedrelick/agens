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

  alias Agens.{Job, Serving}

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

  @doc """
  Generates a random hex-encoded identifier for use as a run, thread, or message id.
  """
  @spec generate_uid() :: binary()
  def generate_uid do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  @typedoc "Summary of a supervised Agens child process."
  @type process_info :: %{
          pid: pid(),
          type: :job | :serving,
          name: binary(),
          config: Job.Config.t() | Serving.Config.t()
        }

  @doc """
  Returns a list of all supervised Agens child processes (Jobs and Servings)
  with their `pid`, `type`, `name`, and configuration.
  """
  @spec active_processes() :: [process_info()]
  def active_processes() do
    Agens
    |> DynamicSupervisor.which_children()
    |> Enum.map(fn {_id, pid, _type, [mod]} ->
      get_process_info(pid, mod)
    end)
  end

  @doc """
  Returns process information for a supervised Agens child given its `pid` and module.

  When the module is `Agens.Job`, the result describes a Job. Otherwise it is treated as a Serving.
  """
  @spec get_process_info(pid(), module()) :: process_info()
  def get_process_info(pid, Job) do
    {:ok, config} = Job.get_config(pid)

    %{pid: pid, type: :job, name: config.id, config: config}
  end

  def get_process_info(pid, _) do
    {:ok, config} = Serving.get_config(pid)

    %{pid: pid, type: :serving, name: Atom.to_string(config.name), config: config}
  end

  @doc """
  Invokes `fun` with `args` on every configured backend module.

  Returns the list of per-backend results in declaration order. See `backends/0`
  for how the backend list is resolved.
  """
  @spec backends(atom(), list()) :: list()
  def backends(fun, args) when is_atom(fun) and is_list(args) do
    backends()
    |> Enum.map(&apply(&1, fun, args))
  end

  @doc """
  Returns the configured list of `Agens.Backend` implementations.

  Reads `:agens` application env key `:backends`, defaulting to
  `[Agens.Backend.Emit, Agens.Backend.Log]`.
  """
  @spec backends() :: [module()]
  def backends() do
    Application.get_env(:agens, :backends, [Agens.Backend.Emit, Agens.Backend.Log])
  end
end
