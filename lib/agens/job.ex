defmodule Agens.Job do
  @moduledoc """
  A Job defines a multi-agent workflow through a sequence of steps.

  An `Agens.Job` is mainly a sequence of steps, defined with the `Agens.Job.Step` struct, used to create advanced multi-agent workflows.

  Conditions can be used in order to route to different steps based on a result, or can be used to end the Job.

  ### Events
  Agens emits several events that can be handled by the caller using `handle_info/3` for purposes such as UI updates, pubsub, logging, persistence and other side effects.

  #### Job
  ```
  {:job_started, job.name}
  ```

  Emitted when a job has started.

  ```
  {:job_ended, job.name, :complete}
  ```

  Emitted when a job has been completed.

  ```
  {:job_error, {job.name, step_index}, {:error, reason | exception}}
  ```

  Emitted when a job has ended due to an error or unhandled exception.

  #### Step
  ```
  {:step_started, {job.name, step_index}, message.input}
  ```

  Emitted when a step has started. Includes the input data provided to the step, whether from the user or a previous step.

  ```
  {:step_result, {job.name, step_index}, message.result}
  ```

  Emitted when a result has been returned from the Serving. Includes the Serving result, which will be passed to the Tool (if applicable), conditions (if applicable), or the next step of the job.

  #### Tool
  The following events are emitted only if the Agent has a Tool specified in `Agens.Agent.Config`:

  ```
  {:tool_started, {job.name, step_index}, message.result}
  ```

  Emitted when a Tool is about to be called. `message.result` here is the Serving result, which will be overriden by the value returned from the Tool prior to final output.

  ```
  {:tool_raw, {job.name, step_index}, message.raw}
  ```

  Emitted after completing the Tool function call. It provides the raw result of the Tool before any post-processing.

  ```
  {:tool_result, {job.name, step_index}, message.result}
  ```

  Emitted after post-processing of the raw Tool result. This is the final result of the Tool, which will be passed to conditions or the next step of the job.
  """

  defmodule Step do
    @moduledoc """
    The Step struct defines a single step within a Job.

    ## Fields
    - `agent` - The name of the agent to be used in the Step.
    - `objective` - An optional string to be added to the LM prompt explaining the purpose of the Step.
    - `conditions` - An optional conditions map to control flow based on the result of the agent.
    """

    @type t :: %__MODULE__{
            agent: atom(),
            objective: String.t() | nil,
            conditions: map() | nil
          }

    @enforce_keys [:agent]
    defstruct [:agent, :objective, :conditions]
  end

  defmodule Config do
    @moduledoc """
    The Config struct defines the details of a Job.

    ## Fields
    - `name` - The unique name used to identify the Job.
    - `description` - An optional string to be added to the LM prompt that describes the basic goal of the Job.
    - `steps` - A list of `Agens.Job.Step` structs that define the sequence of agent actions to be performed.
    """

    @type t :: %__MODULE__{
            name: atom(),
            description: String.t() | nil,
            steps: list(Step.t())
          }

    @enforce_keys [:name, :steps]
    defstruct [:name, :description, :steps]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            status: :init | :running | :error | :completed,
            step_index: non_neg_integer() | nil,
            config: Config.t(),
            parent: pid() | nil
          }

    @enforce_keys [:status, :config]
    defstruct [:status, :step_index, :config, :parent]
  end

  use GenServer

  alias Agens.Message

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts a new Job process using the provided `Agens.Job.Config`.

  `start/1` does not run the Job, only starts the supervised process. See `run/2` for running the Job.
  """
  @spec start(Config.t()) :: {:ok, pid} | {:error, term}
  def start(config) do
    DynamicSupervisor.start_child(Agens, {__MODULE__, config})
  end

  @doc """
  Retrieves the Job configuration by Job name or `pid`.
  """
  @spec get_config(pid | atom) :: {:ok, Config.t()} | {:error, :job_not_found}
  def get_config(job_name) when is_atom(job_name) do
    Agens.name_to_pid(job_name, {:error, :job_not_found}, fn pid -> get_config(pid) end)
  end

  def get_config(pid) when is_pid(pid) do
    {:ok, GenServer.call(pid, :get_config)}
  end

  @doc """
  Runs a Job with the given input by Job name or `pid`.

  A supervised process for the Job must be started first using `start/1`.
  """
  @spec run(pid | atom, String.t()) :: :ok | {:error, :job_not_found}
  def run(job_name, input) when is_atom(job_name) do
    Agens.name_to_pid(job_name, {:error, :job_not_found}, fn pid -> run(pid, input) end)
  end

  def run(pid, input) when is_pid(pid) do
    GenServer.call(pid, {:run, input})
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  @doc false
  @spec child_spec(Config.t()) :: Supervisor.child_spec()
  def child_spec(%Config{} = config) do
    %{
      id: config.name,
      start: {__MODULE__, :start_link, [config]},
      restart: :transient
    }
  end

  @doc false
  @spec start_link(keyword(), Config.t()) :: GenServer.on_start()
  def start_link(extra, config) do
    opts = Keyword.put(extra, :config, config)
    GenServer.start_link(__MODULE__, opts, name: config.name)
  end

  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, State.t()}
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    {:ok, %State{status: :init, config: config}}
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================

  @doc false
  @impl true
  @spec handle_call(:get_config, {pid, term}, State.t()) :: {:reply, Config.t(), State.t()}
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @doc false
  @impl true
  @spec handle_call({:run, String.t()}, {pid, term}, State.t()) :: {:reply, :ok, State.t()}
  def handle_call({:run, _}, _, %{status: :running} = state) do
    {:reply, {:error, :job_already_running}, state}
  end

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
  @spec handle_cast(:end, State.t()) :: {:stop, :normal, State.t()}
  def handle_cast(:end, %State{config: %Config{name: name}} = state) do
    new_state = %State{state | status: :complete}
    send(state.parent, {:job_ended, name, :complete})
    {:stop, :normal, new_state}
  end

  @doc false
  @impl true
  @spec handle_cast({:error, atom()}, State.t()) :: {:stop, :shutdown, State.t()}
  def handle_cast({:error, _reason} = err, %State{config: %Config{name: name}} = state) do
    new_state = %State{state | status: :error}
    send(state.parent, {:job_error, {name, state.step_index}, err})
    {:stop, :shutdown, new_state}
  end

  @doc false
  @impl true
  @spec terminate(:normal | :shutdown | {term(), list()}, State.t()) :: :ok
  def terminate({exception, _}, %State{config: %{name: name}} = state) do
    send(state.parent, {:job_error, {name, state.step_index}, {:error, exception}})
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  @doc false
  @spec do_step(String.t(), State.t()) :: :ok
  defp do_step(input, %State{config: job_config} = state) do
    step = Enum.at(job_config.steps, state.step_index)

    message = %Message{
      parent_pid: state.parent,
      input: input,
      agent_name: step.agent,
      job_name: job_config.name,
      job_description: job_config.description,
      step_index: state.step_index,
      step_objective: step.objective
    }

    send(state.parent, {:step_started, {message.job_name, message.step_index}, message.input})

    message
    |> Message.send()
    |> case do
      %Message{} = message ->
        send(state.parent, {:step_result, {message.job_name, message.step_index}, message.result})

        if step.conditions do
          do_conditions(step.conditions, message)
        else
          GenServer.cast(self(), {:next, message})
        end

      {:error, reason} ->
        GenServer.cast(self(), {:error, reason})
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
        case Map.get(conditions, "__DEFAULT__") do
          :end ->
            GenServer.cast(self(), :end)

          step_index ->
            GenServer.cast(self(), {:step, step_index, message})
        end
    end
  end
end
