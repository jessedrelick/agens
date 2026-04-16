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

  defguard is_status(status)
           when status in [:init, :running, :error, :complete, :paused, :waiting, :stopped]

  defmodule Node do
    @moduledoc """
    The Node struct defines a single node within a Job.

    ## Fields
    - `agent` - The name of the agent to be used in the Node.
    - `objective` - An optional string to be added to the LM prompt explaining the purpose of the Node.
    """

    @type schema :: binary()

    @type t :: %__MODULE__{
            serving: atom(),
            agent_id: any() | nil,
            sub: binary() | nil,
            objective: String.t() | nil,
            tools: list(schema()) | nil,
            resources: list(Agens.Resource.t()) | nil
          }

    @enforce_keys []
    defstruct [:serving, :agent_id, :sub, :objective, :tools, :resources]
  end

  defmodule Sub do
    @type t :: %__MODULE__{
            config: Agens.Job.Config.t(),
            run_id: binary(),
            first_node_id: binary()
          }

    @enforce_keys [:config, :first_node_id]
    defstruct [:config, :run_id, :first_node_id]
  end

  defmodule Config do
    @moduledoc """
    The Config struct defines the details of a Job.

    ## Fields
    - `id` - The unique id used to identify the Job.
    - `description` - An optional string to be added to the LM prompt that describes the basic goal of the Job.
    - `nodes` - A list of `Agens.Job.Node` structs that define the sequence of agent actions to be performed.
    """

    @type t :: %__MODULE__{
            id: binary(),
            description: String.t() | nil,
            nodes: %{
              any() => Node.t()
            },
            outputs: keyword() | nil,
            max_retries: non_neg_integer()
          }

    @enforce_keys [:id, :nodes]
    defstruct [:id, :description, :nodes, :outputs, max_retries: 3]
  end

  defmodule State do
    @moduledoc false

    alias Agens.Message

    defmodule Yield do
      @moduledoc false

      @type thread_id :: binary()
      @type next_node_id :: any()
      @type thread :: {thread_id(), next_node_id()}

      @type t :: %__MODULE__{
              threads: list(thread_id()),
              ready: list(thread())
            }

      @enforce_keys []
      defstruct threads: [], ready: []

      def new(), do: %Yield{}

      def ready?(%Yield{threads: threads, ready: ready}) do
        ready_map = Enum.into(ready, %{})
        Enum.all?(threads, &Map.has_key?(ready_map, &1))
      end

      def thread_ready(nil, thread_id, next_node_id),
        do: thread_ready(%Yield{}, thread_id, next_node_id)

      def thread_ready(%Yield{} = yield, thread_id, next_node_id) do
        Map.update(yield, :ready, [], &[{thread_id, next_node_id} | &1])
      end

      def thread_add(nil, thread_id), do: thread_add(%Yield{}, thread_id)

      def thread_add(%Yield{} = yield, thread_id) do
        Map.update(yield, :threads, [thread_id], &[thread_id | &1])
      end
    end

    @type t :: %__MODULE__{
            status: :init | :running | :error | :completed,
            config: Config.t(),
            caller: pid() | nil,
            run_id: String.t() | nil,
            parent_run_id: String.t() | nil,
            # parent_node_message: Message.t() | nil,
            thread_count: non_neg_integer(),
            tasks: %{
              Task.ref() => Message.t()
            }
          }

    @enforce_keys [:status, :config]
    defstruct [
      :status,
      :config,
      :caller,
      :run_id,
      :parent_run_id,
      # :parent_node_message,
      :yield,
      tasks: %{},
      thread_count: 0
    ]

    @spec get_message(State.t(), Task.ref()) :: Message.t() | nil
    def get_message(%State{} = state, ref) do
      state
      |> Map.get(:tasks)
      |> Map.get(ref)
    end

    @spec add_task(State.t(), Task.ref(), Message.t()) :: State.t()
    def add_task(%State{} = state, ref, %Message{} = message) do
      Map.update!(state, :tasks, fn val -> Map.put(val, ref, message) end)
    end

    @spec remove_task(State.t(), Task.ref()) :: State.t()
    def remove_task(%State{} = state, ref) do
      Map.update!(state, :tasks, fn val -> Map.delete(val, ref) end)
    end

    @spec get_node(State.t(), any()) :: Node.t() | nil
    def get_node(%State{config: job_config}, node_id) do
      Map.get(job_config.nodes, node_id)
    end
  end

  use GenServer

  alias Agens.Message
  alias __MODULE__.State.Yield

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts a new Job process using the provided `Agens.Job.Config`.

  `start/1` does not run the Job, only starts the supervised process. See `run/2` for running the Job.
  """
  @spec start(Config.t(), binary() | nil) :: {:ok, pid} | {:error, term}
  def start(config, run_id \\ nil) do
    :telemetry.execute([:agens, :job, :start], %{}, %{job_id: config.id, run_id: run_id})
    DynamicSupervisor.start_child(Agens, {__MODULE__, {config, run_id}})
  end

  @doc """
  Retrieves the Job configuration by Job name or `pid`.
  """
  @spec get_config(pid | atom | binary()) :: {:ok, Config.t()} | {:error, :job_not_found}
  def get_config(pid) when is_pid(pid) do
    {:ok, GenServer.call(pid, :get_config)}
  end

  def get_config(job_id) when is_binary(job_id) do
    Agens.job_pid(job_id, {:error, :job_not_found}, fn pid -> get_config(pid) end)
  end

  @doc """
  Runs a Job with the given input by Job name or `pid`.

  A supervised process for the Job must be started first using `start/1`.
  """
  @spec run(pid | binary(), String.t(), String.t(), keyword()) :: :ok | {:error, :job_not_found}
  def run(job_id, input, first_node_id, opts) when is_binary(job_id) do
    run_id = Keyword.get(opts, :run_id, nil)
    :telemetry.execute([:agens, :job, :run], %{}, %{job_id: job_id, run_id: run_id})

    if run_id do
      run_id_to_pid(run_id, {:error, :run_not_found}, fn pid ->
        run(pid, input, first_node_id, opts)
      end)
    else
      Agens.job_pid(job_id, {:error, :job_not_found}, fn pid ->
        run(pid, input, first_node_id, opts)
      end)
    end
  end

  def run(pid, input, first_node_id, opts) when is_pid(pid) do
    GenServer.call(pid, {:run, input, first_node_id, opts})
  end

  def stop(run_id) do
    :telemetry.execute([:agens, :job, :stop], %{}, %{run_id: run_id})

    run_id_to_pid(run_id, {:error, :run_not_found}, fn pid ->
      change_status(run_id, :stopped)
      GenServer.stop(pid, :normal)
    end)
  end

  defp change_status(run_id, status) when is_status(status) do
    :telemetry.execute([:agens, :job, :status], %{}, %{status: status, run_id: run_id})

    run_id_to_pid(run_id, {:error, :run_not_found}, fn pid ->
      GenServer.cast(pid, {:change_status, status})
    end)
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  @doc false
  @spec child_spec({Config.t(), binary() | nil}) :: Supervisor.child_spec()
  def child_spec({%Config{} = config, run_id}) do
    %{
      id: config.id,
      start: {__MODULE__, :start_link, [{config, run_id}]},
      restart: :transient
    }
  end

  @doc false
  @spec start_link(keyword(), {Config.t(), binary() | nil}) :: GenServer.on_start()
  def start_link(extra, {config, run_id}) do
    opts =
      extra
      |> Keyword.put(:config, config)
      |> Keyword.put(:run_id, run_id)

    GenServer.start_link(__MODULE__, opts, name: via(config.id, run_id))
  end

  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, State.t()}
  def init(opts) do
    config = Keyword.fetch!(opts, :config)
    run_id = Keyword.fetch!(opts, :run_id)
    {:ok, %State{status: :init, config: config, run_id: run_id}}
  end

  # ===========================================================================
  # Call
  # ===========================================================================

  @doc false
  @impl true
  @spec handle_call(:get_config, {pid, term}, State.t()) :: {:reply, Config.t(), State.t()}
  def handle_call(:get_config, _from, %State{} = state) do
    {:reply, state.config, state}
  end

  @doc false
  @impl true
  @spec handle_call({:run, String.t(), any(), keyword()}, {pid, term}, State.t()) ::
          {:reply, :ok, State.t()}
  def handle_call({:run, _, _, _}, _, %State{status: :running} = state) do
    {:reply, {:error, :job_already_running}, state}
  end

  def handle_call({:run, nil, _, _}, _, %State{} = state) do
    {:reply, {:error, :input_required}, state}
  end

  def handle_call({:run, input, first_node_id, opts}, {pid, _}, %State{} = state) do
    caller = Keyword.get(opts, :caller, pid)
    new_state = %State{state | status: :running, caller: caller}
    parent_run_id = Keyword.get(opts, :parent_run_id, nil)
    # parent_node_message = Keyword.get(opts, :parent_node_message, nil)

    new_state =
      if parent_run_id, do: %State{new_state | parent_run_id: parent_run_id}, else: new_state

    # new_state =
    #   if parent_node_message,
    #     do: %State{new_state | parent_node_message: parent_node_message},
    #     else: new_state

    {:reply, :ok, new_state, {:continue, {:run, input, first_node_id}}}
  end

  @doc false
  @impl true
  @spec handle_continue({:run, String.t(), String.t()}, State.t()) :: {:noreply, State.t()}
  def handle_continue({:run, input, first_node_id}, %State{config: %{id: id}} = state) do
    server_pid = self()
    first_thread_id = generate_thread_id()
    Agens.backends(:start, [state.caller, id, state.run_id])
    change_status(state.run_id, :running)
    GenServer.cast(server_pid, {:thread, first_thread_id})

    message = %Message{
      job_id: state.config.id,
      job_description: state.config.description,
      run_id: state.run_id,
      parent_run_id: state.parent_run_id,
      input: input,
      node_id: first_node_id,
      caller: state.caller,
      thread_id: first_thread_id
    }

    {:noreply, do_node(message, server_pid, state)}
  end

  # ===========================================================================
  # Cast
  # ===========================================================================

  @doc false
  @impl true
  @spec handle_cast({{:route, any()}, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast(
        {{:route, node_id}, %Message{result: result} = message},
        %State{config: %Config{nodes: nodes}} = state
      )
      when is_map(nodes) do
    server_pid = self()

    message =
      message
      |> Map.put(:node_id, node_id)
      |> Map.put(:previous_result, result)
      |> Map.put(:result, nil)

    {:noreply, do_node(message, server_pid, state)}
  end

  @doc false
  @impl true
  @spec handle_cast({{:yield, any()}, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({{:yield, node_id}, %Message{} = message}, %State{} = state) do
    yield = Yield.thread_ready(state.yield, message.thread_id, node_id)
    total_count = length(yield.threads)
    ready_count = length(yield.ready)
    new_count = state.thread_count - 1

    if Yield.ready?(yield) do
      :telemetry.execute([:agens, :job, :yield_done], %{}, %{run_id: state.run_id})
      Agens.backends(:yield_done, [state.caller, message, total_count])
      GenServer.cast(self(), {{:route, node_id}, message})
      {:noreply, %{state | yield: Yield.new(), thread_count: new_count + 1}}
    else
      :telemetry.execute([:agens, :job, :yield_wait], %{}, %{run_id: state.run_id})
      Agens.backends(:yield_wait, [state.caller, message, total_count, ready_count])
      {:noreply, %{state | yield: yield, thread_count: new_count}}
    end
  end

  @doc false
  @impl true
  @spec handle_cast({{:sub, any()}, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({{:sub, job_id}, %Message{} = message}, %State{} = state) do
    run_sub(state, message, job_id)

    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_cast({{:retry, any()}, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast(
        {{:retry, _reason}, %Message{retries: retries} = message},
        %State{config: %{max_retries: max}} = state
      )
      when retries >= max do
    GenServer.cast(self(), {{:error, :max_retries}, message})

    {:noreply, state}
  end

  def handle_cast({{:retry, reason}, %Message{} = message}, %State{} = state) do
    message =
      message
      |> Map.update(:retries, 1, &(&1 + 1))
      |> Map.put(:retry_reason, reason)

    :telemetry.execute([:agens, :job, :retry], %{}, %{
      run_id: state.run_id,
      retry: message.retries
    })

    Agens.backends(:node_retry, [state.caller, message])

    message = Map.put(message, :result, nil)
    GenServer.cast(self(), {{:route, message.node_id}, message})

    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_cast({:done, Message.t()}, State.t()) ::
          {:noreply, State.t()} | {:stop, :normal, State.t()}
  def handle_cast({:done, message}, %State{} = state) do
    new_count = state.thread_count - 1

    if new_count == 0 do
      # if state.parent_node_message do
      #   node_result = %{state.parent_node_message | result: message.result}
      #   Agens.backends(:node_result, [state.caller, node_result])
      # end

      maybe_notify_parent(state, {:done, message})

      :telemetry.execute([:agens, :job, :complete], %{}, %{run_id: state.run_id})
      change_status(state.run_id, :complete)
      Agens.backends(:complete, [state.caller, state.run_id])
      {:stop, :normal, %{state | thread_count: 0}}
    else
      {:noreply, %{state | thread_count: new_count}}
    end
  end

  @doc false
  @impl true
  @spec handle_cast({:end, Message.t()}, State.t()) :: {:stop, :normal, State.t()}
  def handle_cast({:end, message}, %State{} = state) do
    maybe_notify_parent(state, {:done, message})

    :telemetry.execute([:agens, :job, :end], %{}, %{run_id: state.run_id})

    change_status(state.run_id, :complete)
    Agens.backends(:complete, [state.caller, state.run_id])

    {:stop, :normal, state}
  end

  @doc false
  @impl true
  @spec handle_cast({{:error, any()}, Message.t()}, State.t()) :: {:stop, :shutdown, State.t()}
  def handle_cast({{:error, reason}, message}, %State{} = state) do
    :telemetry.execute([:agens, :job, :error], %{}, %{run_id: state.run_id})
    change_status(state.run_id, :error)
    Agens.backends(:error, [state.caller, message, reason])

    {:stop, :shutdown, state}
  end

  @doc false
  @impl true
  @spec handle_cast({:change_status, atom()}, State.t()) :: {:reply, State.t()}
  def handle_cast({:change_status, status}, %State{} = state) do
    new_state = %State{state | status: status}
    Agens.backends(:status, [state.caller, state.run_id, status])
    {:noreply, new_state}
  end

  @doc false
  @impl true
  @spec handle_cast({:thread, binary()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:thread, thread_id}, %State{} = state) do
    yield = Yield.thread_add(state.yield, thread_id)
    {:noreply, %{state | yield: yield, thread_count: state.thread_count + 1}}
  end

  # ===========================================================================
  # Info
  # ===========================================================================

  @doc false
  @impl true
  @spec handle_info({Task.ref(), any()} | {:DOWN, Task.ref(), :process, pid(), any()}, State.t()) ::
          {:noreply, State.t()}
  def handle_info({ref, _result}, %State{} = state) do
    Process.demonitor(ref, [:flush])
    {:noreply, State.remove_task(state, ref)}
  end

  @doc false
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, error}, %State{} = state) do
    Process.demonitor(ref, [:flush])
    message = State.get_message(state, ref)
    Agens.backends(:error, [state.caller, message, error])
    {:noreply, State.remove_task(state, ref)}
  end

  # ===========================================================================
  # Terminate
  # ===========================================================================

  @doc false
  @impl true
  @spec terminate(:normal | :shutdown | {term(), list()}, State.t()) :: :ok
  def terminate({exception, _}, %State{} = state) do
    change_status(state.run_id, :error)
    message = %Message{input: "", caller: state.caller, run_id: state.run_id}
    Agens.backends(:error, [state.caller, message, exception])

    :ok
  end

  def terminate(_reason, %State{}) do
    :ok
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  @doc false
  @spec do_node(Message.t(), pid(), State.t()) :: State.t()
  defp do_node(message, server_pid, %State{config: job_config} = state) do
    node = State.get_node(state, message.node_id)

    cond do
      is_nil(node) ->
        GenServer.cast(server_pid, {{:error, :invalid_node}, message})

        state

      not is_nil(node.sub) ->
        message = %Message{
          caller: state.caller,
          run_id: state.run_id,
          parent_run_id: state.parent_run_id,
          job_id: job_config.id,
          job_description: job_config.description,
          agent_id: node.agent_id,
          node_id: message.node_id,
          input: message.input,
          previous_result: message.previous_result,
          result: message.input,
          thread_id: message.thread_id
        }

        Agens.backends(:node_started, [state.caller, message])

        run_sub(state, message, node.sub)

        state

      true ->
        message = %Message{
          caller: state.caller,
          run_id: state.run_id,
          parent_run_id: state.parent_run_id,
          job_id: job_config.id,
          job_description: job_config.description,
          serving_name: node.serving,
          agent_id: node.agent_id,
          node_objective: node.objective,
          tool_defs: node.tools,
          resources: node.resources,
          node_id: message.node_id,
          input: message.input,
          previous_result: message.previous_result,
          retries: message.retries,
          retry_reason: message.retry_reason,
          tool_calls: message.tool_calls,
          tool_results: message.tool_results,
          thread_id: message.thread_id
        }

        Agens.backends(:node_started, [state.caller, message])

        task =
          Task.Supervisor.async_nolink(Agens.JobSupervisor, fn ->
            message = load_resources(message, state)

            message
            |> Message.send()
            |> handle_result(message, server_pid, state)
          end)

        State.add_task(state, task.ref, message)
    end
  end

  defp handle_result({:retry, reason}, %Message{} = message, server_pid, %State{}) do
    GenServer.cast(server_pid, {{:retry, reason}, message})
  end

  defp handle_result({:error, reason}, %Message{} = original, server_pid, %State{}) do
    GenServer.cast(server_pid, {{:error, reason}, original})
  end

  defp handle_result(
         %Message{tool_calls: tool_calls} = message,
         original,
         server_pid,
         %State{} = state
       )
       when is_list(tool_calls) and length(tool_calls) > 0 do
    %{config: %Config{id: job_id}, run_id: run_id} = state

    incomplete_calls = incomplete_tool_calls(tool_calls, message.tool_results)

    if length(incomplete_calls) < 1 do
      message = %Message{message | tool_calls: nil}
      handle_result(message, original, server_pid, state)
    else
      new_results =
        incomplete_calls
        |> Enum.map(fn %{"arguments" => arguments} = tool_call ->
          input =
            arguments
            |> Enum.map(fn %{"key" => k, "value" => v} -> {k, v} end)
            |> Enum.into(%{})

          Map.put(tool_call, "input", input)
        end)
        |> Task.async_stream(
          fn args ->
            tool_name = args["name"]
            Agens.backends(:tool_call, [state.caller, job_id, run_id, tool_name])

            :telemetry.execute([:agens, :tool, :call], %{}, %{
              job_id: job_id,
              run_id: run_id,
              tool: tool_name
            })

            Agens.Serving.call_tool(message.serving_name, args, message)
          end,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)
        |> Enum.into(%{})

      message
      |> Map.update!(:tool_results, fn existing_results ->
        Map.merge(existing_results || %{}, new_results)
      end)
      |> do_node(server_pid, state)
    end
  end

  defp handle_result(%Message{} = message, original, server_pid, %State{} = state) do
    Agens.backends(:node_result, [state.caller, message])
    message = Map.put(message, :retry_reason, nil)
    do_next(message, original, server_pid, state)
  end

  defp do_next(%Message{next: next} = message, _, server_pid, %State{}) when is_list(next) do
    if n = end_or_retry?(next) do
      GenServer.cast(server_pid, {n, message})
    else
      case get_instructions(next) do
        [] ->
          GenServer.cast(server_pid, {:done, message})

        instructions ->
          instructions
          |> Enum.with_index()
          |> Enum.each(fn {instruction, index} ->
            msg =
              if index == 0 do
                message
              else
                thread_id = generate_thread_id()
                GenServer.cast(server_pid, {:thread, thread_id})
                Map.put(message, :thread_id, thread_id)
              end

            GenServer.cast(server_pid, {instruction, msg})
          end)
      end
    end
  end

  defp do_next(%Message{next: _invalid_next} = message, _, server_pid, %State{}) do
    GenServer.cast(server_pid, {{:error, :invalid_next}, message})
  end

  defp end_or_retry?(next) do
    cond do
      :end in next ->
        :end

      true ->
        Enum.find(next, &match?({:retry, _}, &1)) ||
          if(:retry in next, do: {:retry, nil})
    end
  end

  defp get_instructions(next) do
    yields = Enum.filter(next, &match?({:yield, _}, &1))
    subs = Enum.filter(next, &match?({:sub, _}, &1))

    next
    |> Enum.filter(&match?({:route, _, _}, &1))
    |> Enum.flat_map(fn {:route, node_id, count} ->
      List.duplicate({:route, node_id}, count)
    end)
    |> Enum.concat(yields)
    |> Enum.concat(subs)
  end

  # ===========================================================================
  # Utilities
  # ===========================================================================

  defp run_sub(state, message, job_id) do
    spec =
      :sub
      |> Agens.backends([self(), job_id])
      |> Enum.find(&match?(%Agens.Job.Sub{}, &1))

    if !spec do
      GenServer.cast(self(), {{:error, :job_not_loaded}, message})
    else
      %{config: config, run_id: run_id, first_node_id: first_node_id} = spec

      start(config, run_id)

      run(config.id, message.input, first_node_id,
        run_id: run_id,
        parent_run_id: state.run_id,
        caller: state.caller
        # parent_node_message: message
      )
    end
  end

  defp maybe_notify_parent(%State{parent_run_id: nil}, _msg), do: :ok

  defp maybe_notify_parent(
         %State{parent_run_id: parent_run_id} = state,
         {_, %Message{} = message} = msg
       ) do
    Agens.backends(:node_result, [state.caller, message])

    run_id_to_pid(parent_run_id, :ok, fn pid ->
      GenServer.cast(pid, msg)
    end)
  end

  defp load_resources(%Message{resources: resources} = message, _state)
       when is_nil(resources) or resources == [],
       do: message

  defp load_resources(%Message{resources: resources} = message, _state) do
    loaded =
      resources
      |> Task.async_stream(
        fn resource ->
          Agens.Serving.load_resource(message.serving_name, resource, message)
        end,
        ordered: true
      )
      |> Enum.map(fn {:ok, resource} -> resource end)

    %Message{message | resources: loaded}
  end

  defp incomplete_tool_calls(calls, nil), do: calls

  defp incomplete_tool_calls(calls, results) do
    Enum.reject(calls, fn call -> Map.has_key?(results, call["id"]) end)
  end

  defp generate_thread_id() do
    generate_thread_id(nil)
  end

  defp generate_thread_id(nil) do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode16(case: :lower)
  end

  defp generate_thread_id(thread_id) when is_binary(thread_id), do: thread_id

  @spec run_id_to_pid(any(), {:error, term()}, (pid() -> any())) :: any()
  defp run_id_to_pid(run_id, err, cb) do
    name = via(nil, run_id)

    case GenServer.whereis(name) do
      nil -> err
      pid when is_pid(pid) -> cb.(pid)
    end
  end

  defp via(_, run_id) when not is_nil(run_id) do
    {:via, Registry, {Agens.Registry, String.to_atom(run_id)}}
  end

  defp via(job_id, nil) do
    {:via, Registry, {Agens.Registry, job_id}}
  end
end
