defmodule Agens.Job do
  @moduledoc """
  A Job defines a multi-agent workflow through a sequence of steps.

  An `Agens.Job` is mainly a sequence of steps, defined with the `Agens.Job.Step` struct, used to create advanced multi-agent workflows.

  Conditions can be used in order to route to different steps based on a result, or can be used to end the Job.
  """

  defmodule Step do
    @moduledoc """
    The Step struct defines a single step within a Job.

    ## Fields
    - `agent` - The name of the agent to be used in the Step.
    - `prompt` - An optional string to be added to the LM prompt.
    - `conditions` - An optional conditions map to control flow based on the result of the agent.
    """

    @type t :: %__MODULE__{
            agent: atom(),
            prompt: String.t() | nil,
            conditions: map() | nil
          }

    @enforce_keys [:agent]
    defstruct [:agent, :prompt, :conditions]
  end

  defmodule Config do
    @moduledoc """
    The Config struct defines the details of a Job.

    ## Fields
    - `name` - An atom that identifies the Job.
    - `objective` - A optional string to be added to the LM prompt that describes the purpose of the Job.
    - `steps` - A list of `Agens.Job.Step` structs that define the sequence of agent actions to be performed.
    """

    @type t :: %__MODULE__{
            name: atom(),
            objective: String.t() | nil,
            steps: list(Step.t())
          }

    @enforce_keys [:name, :steps]
    defstruct [:name, :objective, :steps]
  end

  defmodule State do
    @moduledoc false

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
  Starts a new Job process using the provided `Agens.Job.Config`.

  `start/1` does not run the Job, only starts the supervised process. See `run/2` for running the Job.
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
  Runs a Job with the given input by Job name or `pid`.

  A supervised process for the Job must be started first using `start/1`.
  """
  @spec run(pid | atom, term) :: {:ok, term} | {:error, :job_not_found}
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

  def run(pid, input) when is_pid(pid) do
    GenServer.call(pid, {:run, input})
  end

  @doc """
  Retrieves the Job configuration by Job name or `pid`.
  """
  @spec get_config(pid | atom) :: {:ok, term} | {:error, :job_not_found}
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

  def get_config(pid) when is_pid(pid) do
    GenServer.call(pid, :get_config)
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
