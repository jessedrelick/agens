defmodule Agens.Job do
  @moduledoc """
  A `GenServer` implementation that manages a sequence of steps.

  The job is defined by a `Config` struct that specifies the name, objective,
  and sequence of steps. Each step is defined by an `Agent` struct and a
  prompt string. The job can be started using the `start/1` function and
  run using the `run/2` function. The progress of the job can be observed
  using the `GenServer.call/2` and `GenServer.cast/2` functions to retrieve
  the current state of the job and to control its progression.
  """
  use GenServer

  defmodule Step do
    @moduledoc """
    The `Step` struct defines a step in a job.

    A step consists of an `Agent` struct and a prompt string. Optionally, a list of
    conditions can be specified to control if the step should be executed.
    """

    @type t :: %__MODULE__{
            agent: atom(),
            prompt: String.t() | nil,
            conditions: list(map()) | nil
          }

    @enforce_keys [:agent]
    defstruct [:agent, :prompt, :conditions]
  end

  defmodule Config do
    @moduledoc """
    The `Config` struct defines the configuration for a job.

    The `name` field is an atom that identifies the job. The `objective` field
    is a string that describes the purpose of the job. The `steps` field is a list
    of `Step` structs that define the sequence of actions to be performed.
    """
    defstruct [:name, :objective, :steps]

    @typedoc """
    The `Config` struct defines the configuration for a job.

    The `name` field is a string that identifies the job. The `objective` field
    is a string that describes the purpose of the job. The `steps` field is a list
    of `Step` structs that define the sequence of actions to be performed.
    """
    @type t :: %__MODULE__{
            name: String.t(),
            objective: String.t(),
            steps: list(Step.t())
          }
  end

  defmodule State do
    @moduledoc """
    The `State` struct is used to keep track of the current state of a job.

    The `status` field is one of `:running`, `:error`, or `:completed`. The
    `step_index` field is an integer that represents the index of the current
    step being executed. The `config` field is a `Config` struct that defines the
    configuration for the job. The `parent` field is a process identifier for the
    parent process.
    """

    @type t :: %__MODULE__{
            status: :init | :running | :error | :completed,
            step_index: non_neg_integer(),
            config: Config.t(),
            parent: pid()
          }

    @enforce_keys [:status]
    defstruct [:status, :step_index, :config, :parent]
  end

  require Logger

  alias Agens.{Agent, Job}

  @doc """
  Starts a new job using the provided `config`.

  Returns `{:ok, pid}` if the job was successfully started.
  """
  @spec start(Config.t()) :: {:ok, pid} | {:error, term}
  def start(config) do
    spec = Job.child_spec(config)

    pid =
      Agens
      |> DynamicSupervisor.start_child(spec)
      |> case do
        {:ok, pid} ->
          pid

        {:error, {:already_started, pid}} ->
          Logger.warning("Agent #{config.name} already started")
          pid
      end

    {:ok, pid}
  end

  @doc """
  Runs a job with the given `pid` and `input`.

  Returns the result of the `GenServer.call/2` function.
  """
  @spec run(pid, term) :: term
  @spec run(atom, term) :: {:ok, term} | {:error, :job_not_found}
  def run(pid, input) when is_pid(pid) do
    GenServer.call(pid, {:start, input})
  end

  def run(name, input) when is_atom(name) do
    name
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :job_not_found}

      pid when is_pid(pid) ->
        run(pid, input)
    end
  end

  @doc """
  Retrieves the configuration for a job with the given `pid`.

  Returns the result of the `GenServer.call/2` function.
  """
  @spec get_config(pid) :: term
  @spec get_config(atom) :: {:ok, term} | {:error, :job_not_found}
  def get_config(pid) when is_pid(pid) do
    GenServer.call(pid, :get_config)
  end

  def get_config(name) when is_atom(name) do
    name
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :job_not_found}

      pid when is_pid(pid) ->
        get_config(pid)
    end
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config.name)
  end

  def child_spec(config) do
    %{
      id: config.name,
      start: {__MODULE__, :start_link, [config]},
      type: :worker,
      restart: :transient
    }
  end

  @impl true
  def init(config) do
    {:ok, %State{status: :init, config: config}}
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @impl true
  def handle_call({:start, input}, {parent, _}, state) do
    new_state = %State{state | status: :running, step_index: 0, parent: parent}
    {:reply, :ok, new_state, {:continue, {:start, input}}}
  end

  @impl true
  def handle_continue({:start, input}, %{config: %{name: name}} = state) do
    send(state.parent, {:job_started, name})
    do_step(input, state)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:next, input}, %State{step_index: index} = state) do
    new_state = %State{state | step_index: index + 1}
    do_step(input, new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:step, index, input}, %State{} = state) do
    unless is_integer(index) do
      raise "Invalid step index: #{inspect(index)}"
    end

    new_state = %State{state | step_index: index}
    do_step(input, new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:end, %State{} = state) do
    new_state = %State{state | status: :complete}
    {:stop, :complete, new_state}
  end

  @impl true
  def terminate(:complete, %State{config: %{name: name}} = state) do
    send(state.parent, {:job_ended, name, :complete})
    :ok
  end

  @impl true
  def terminate({error, _}, %State{config: %{name: name}} = state) do
    send(state.parent, {:job_ended, name, {:error, error}})
    :ok
  end

  defp do_step(input, %State{config: config} = state) do
    step = Enum.at(config.steps, state.step_index)

    send(state.parent, {:step_started, config.name, state.step_index, input})
    {:ok, text} = Agent.message(step.agent, input)
    send(state.parent, {:step_result, config.name, state.step_index, text})

    if step.conditions do
      do_conditions(step.conditions, text, input)
    else
      GenServer.cast(self(), {:next, text})
    end
  end

  defp do_conditions(conditions, text, input) when is_map(conditions) do
    conditions
    |> Map.get(text)
    |> case do
      :end ->
        GenServer.cast(self(), :end)

      nil ->
        step_index = Map.get(conditions, "__DEFAULT__")
        GenServer.cast(self(), {:step, step_index, input})
    end
  end

  defp do_conditions(_conditions, _text, _input) do
    {:error, :not_implemented}
  end
end
