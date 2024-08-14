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

    @type t :: %__MODULE__{
            name: String.t(),
            objective: String.t(),
            steps: list(Step.t())
          }

    @enforce_keys [:name, :steps]
    defstruct [:name, :objective, :steps]
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

  use GenServer

  require Logger

  alias Agens.{Agent, Job, Message}

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
  @spec run(pid | atom, term) :: {:ok, term} | {:error, :job_not_found}
  def run(pid, input) when is_pid(pid) do
    GenServer.call(pid, {:run, input})
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
  @spec get_config(pid | atom) :: {:ok, term} | {:error, :job_not_found}
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

  @doc false
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config.name)
  end

  @doc false
  def child_spec(config) do
    %{
      id: config.name,
      start: {__MODULE__, :start_link, [config]},
      type: :worker,
      restart: :transient
    }
  end

  @doc false
  @impl true
  @spec init(Config.t()) :: {:ok, State.t()}
  def init(config) do
    {:ok, %State{status: :init, config: config}}
  end

  @doc false
  @impl true
  @spec handle_call(:get_config, {pid, term}, State.t()) :: {:reply, Config.t(), State.t()}
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @doc false
  @impl true
  @spec handle_call({:run, String.t()}, {pid, term}, State.t()) :: {:reply, :ok, State.t()}
  def handle_call({:run, input}, {parent, _}, state) do
    new_state = %State{state | status: :running, step_index: 0, parent: parent}
    {:reply, :ok, new_state, {:continue, {:run, input}}}
  end

  @doc false
  @impl true
  @spec handle_continue({:run, String.t()}, State.t()) :: {:noreply, State.t()}
  def handle_continue({:run, input}, %{config: %{name: name}} = state) do
    send(state.parent, {:job_started, name})
    do_step(input, state)
    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_cast({:next, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:next, %Message{} = message}, %State{step_index: index} = state) do
    new_state = %State{state | step_index: index + 1}
    do_step(message.result, new_state)
    {:noreply, new_state}
  end

  @doc false
  @impl true
  @spec handle_cast({:step, integer, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:step, index, %Message{} = message}, %State{} = state) do
    unless is_integer(index) do
      raise "Invalid step index: #{inspect(index)}"
    end

    new_state = %State{state | step_index: index}
    do_step(message.result, new_state)
    {:noreply, new_state}
  end

  @doc false
  @impl true
  @spec handle_cast(:end, State.t()) :: {:stop, :complete, State.t()}
  def handle_cast(:end, %State{} = state) do
    new_state = %State{state | status: :complete}
    {:stop, :complete, new_state}
  end

  @doc false
  @impl true
  @spec terminate(:complete | {:error, term}, State.t()) :: :ok
  def terminate(:complete, %State{config: %{name: name}} = state) do
    send(state.parent, {:job_ended, name, :complete})
    :ok
  end

  def terminate({error, _}, %State{config: %{name: name}} = state) do
    send(state.parent, {:job_ended, name, {:error, error}})
    :ok
  end

  @doc false
  @spec do_step(String.t(), State.t()) :: :ok
  defp do_step(input, %State{config: job_config} = state) do
    step = Enum.at(job_config.steps, state.step_index)

    message = %Message{
      parent_pid: state.parent,
      input: input,
      agent_name: step.agent,
      job_name: job_config.name,
      step_index: state.step_index
    }

    send(state.parent, {:step_started, message.job_name, message.step_index, message.input})
    message = Agent.message(message)
    send(state.parent, {:step_result, message.job_name, message.step_index, message.result})

    if step.conditions do
      do_conditions(step.conditions, message)
    else
      GenServer.cast(self(), {:next, message})
    end
  end

  @doc false
  @spec do_conditions(map(), Message.t()) :: :ok
  defp do_conditions(conditions, %Message{} = message) when is_map(conditions) do
    conditions
    |> Map.get(message.result)
    |> case do
      :end ->
        GenServer.cast(self(), :end)

      nil ->
        step_index = Map.get(conditions, "__DEFAULT__")
        GenServer.cast(self(), {:step, step_index, message})
    end
  end
end
