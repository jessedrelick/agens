defmodule Agens.Job do
  @moduledoc """
  A Job defines a multi-agent workflow as a graph of `Agens.Job.Node`s.

  A Job is a map of `node_id => Agens.Job.Node` plus a `:starting_node_id`. Each Node declares a
  Serving and, optionally, an objective, tools, resources, or a Sub-Job. Routing between Nodes is
  dynamic and graph-based: the Serving's Router returns `next` instructions
  (`{:route, node_id, count}`, `{:yield, node_id}`, `{:sub, job_id}`, `:end`, `:retry`) based on the
  Node's structured outputs. There is no static `next` field on a Node — the graph is defined entirely
  by the routing decisions emitted at runtime.

  ### Events

  Lifecycle and per-Node activity are surfaced through the `Agens.Backend` behaviour. Configured
  backends (see `Agens.backends/0` for the defaults) receive callbacks for every significant event.
  The default emit backend forwards them to the caller process as messages, suitable for
  `handle_info/2` in a UI/pubsub layer; the default log backend writes structured logs. Implement
  your own `Agens.Backend` for custom persistence or side effects.

  The default emit backend sends:

  #### Job

      {:job_started, job_id, run_id}
      {:job_status, {run_id, status}}
      {:job_complete, run_id}
      {:job_error, message, error}

  #### Node

      {:node_started, message}
      {:node_retry, message}
      {:node_result, message}

  #### Tool / Resource / Prompt

  The following are emitted when applicable (e.g. `:tool_call` only when the Node has `:tools` set,
  `:resource_load` only when `:resources` are configured):

      {:tool_call, message, tool_call}
      {:resource_load, message, resource}
      {:prompt, {system, user}}

  #### Yield

  Emitted while a yielding Node waits on, or aggregates, parallel threads:

      {:yield_wait, {message, total_count, ready_count}}
      {:yield_done, {message, total_count}}

  ## Routing and Sub-Jobs

  Every `Agens.Job.Node` declares a `:serving`, even when it also declares `:sub`. The Node's Serving owns routing: the parent Node's `next` instructions are always produced by the Serving's router (`c:Agens.Serving.handle_result/3` for normal inference, `c:Agens.Serving.handle_sub/3` for a resolved Sub-Job). There is no static `next` field on `Agens.Job.Node` — all routing is dynamic.

  Two distinct Sub flows are supported:

  - **Sub Node** (`Agens.Job.Node` with `:sub` set) — the Sub-Job runs *in place of* inference on the parent Node. When the Sub completes, the parent invokes `c:Agens.Serving.handle_sub/3` on the Node's declared Serving to map the Sub's final `Agens.Message` into the parent Node's `outputs` and `next`.
  - **Sub via routing instruction** (`{:sub, job_id}` returned in a Serving's `next`) — the Sub-Job runs as additional work *after* the Node's inference has completed and routing was already decided. The Sub's terminal message drives subsequent routing in the parent; `handle_sub/3` is not invoked.

  Configuration is validated on `start/2`. Missing `:serving` on any Node raises `ArgumentError` immediately rather than failing at runtime.
  """

  defguard is_status(status)
           when status in [:running, :error, :complete, :ended, :stopped]

  use GenServer

  alias Agens.Job.{Config, State, Sub, Yield}
  alias Agens.Job.Node, as: JobNode
  alias Agens.Message

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts a new Job process using the provided `Agens.Job.Config`.

  `start/1` does not run the Job, only starts the supervised process. See `run/2` for running the Job.
  """
  @spec start(Config.t(), binary()) :: {:ok, pid} | {:error, term}
  def start(config, run_id) do
    Config.validate!(config)
    :telemetry.execute([:agens, :job, :start], %{}, %{job_id: config.id, run_id: run_id})
    DynamicSupervisor.start_child(Agens, {__MODULE__, {config, run_id}})
  end

  @doc """
  Retrieves the Job configuration by Job name or `pid`.
  """
  @spec get_config(pid | binary()) :: {:ok, Config.t()} | {:error, :run_not_found}
  def get_config(pid) when is_pid(pid) do
    {:ok, GenServer.call(pid, :get_config)}
  end

  def get_config(run_id) when is_binary(run_id) do
    run_id_to_pid(run_id, {:error, :run_not_found}, fn pid -> get_config(pid) end)
  end

  @doc """
  Runs a Job with the given input by Job name or `pid`.

  A supervised process for the Job must be started first using `start/1`.
  """
  @spec run(pid | binary(), String.t(), keyword()) ::
          :ok | {:error, :run_not_found | :job_already_running | :input_required}
  def run(run_id, input, opts) when is_binary(run_id) do
    run_id_to_pid(run_id, {:error, :run_not_found}, fn pid ->
      run(pid, input, opts)
    end)
  end

  def run(pid, input, opts) when is_pid(pid) do
    GenServer.call(pid, {:run, input, opts})
  end

  @doc """
  Stops a running Job by `run_id`.

  Returns `:ok` when the Job process is found and stopped, or
  `{:error, :run_not_found}` if no Job is running under the given `run_id`.
  """
  @spec stop(binary()) :: :ok | {:error, :run_not_found}
  def stop(run_id) do
    :telemetry.execute([:agens, :job, :stop], %{}, %{run_id: run_id})

    run_id_to_pid(run_id, {:error, :run_not_found}, fn pid ->
      GenServer.call(pid, :stop)
    end)
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  @doc false
  @spec child_spec({Config.t(), binary()}) :: Supervisor.child_spec()
  def child_spec({%Config{} = config, run_id}) do
    %{
      id: run_id,
      start: {__MODULE__, :start_link, [{config, run_id}]},
      restart: :transient
    }
  end

  @doc false
  @spec start_link(keyword(), {Config.t(), binary()}) :: GenServer.on_start()
  def start_link(extra, {config, run_id}) do
    opts =
      extra
      |> Keyword.put(:config, config)
      |> Keyword.put(:run_id, run_id)

    GenServer.start_link(__MODULE__, opts, name: via(run_id))
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
  @spec handle_call(:stop, {pid, term}, State.t()) :: {:stop, :normal, :ok, State.t()}
  def handle_call(:stop, _from, %State{} = state) do
    state = change_status(state, :stopped)
    {:stop, :normal, :ok, state}
  end

  @doc false
  @impl true
  @spec handle_call({:run, String.t(), keyword()}, {pid, term}, State.t()) ::
          {:reply, :ok | {:error, :job_already_running | :input_required}, State.t()}
  def handle_call({:run, _, _}, _, %State{status: :running} = state) do
    {:reply, {:error, :job_already_running}, state}
  end

  def handle_call({:run, nil, _}, _, %State{} = state) do
    {:reply, {:error, :input_required}, state}
  end

  def handle_call({:run, input, opts}, {pid, _}, %State{} = state) do
    :telemetry.execute([:agens, :job, :run], %{}, %{job_id: state.config.id, run_id: state.run_id})

    caller = Keyword.get(opts, :caller, pid)
    sub = Keyword.get(opts, :sub)

    new_state = %State{state | status: :running, caller: caller, sub: sub}

    {:reply, :ok, new_state, {:continue, {:run, input}}}
  end

  @doc false
  @impl true
  @spec handle_continue({:run, String.t()}, State.t()) :: {:noreply, State.t()}
  def handle_continue(
        {:run, input},
        %State{config: %{id: id, starting_node_id: first_node_id}} = state
      ) do
    server_pid = self()
    first_thread_id = Agens.generate_uid()
    Agens.backends(:start, [state.caller, id, state.run_id])
    state = change_status(state, :running)
    GenServer.cast(server_pid, {:thread, first_thread_id})

    message = %Message{
      job_id: state.config.id,
      job_description: state.config.description,
      run_id: state.run_id,
      parent_run_id: state.sub && state.sub.parent_run_id,
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
      new_yield = Yield.thread_add(Yield.new(), message.thread_id)
      {:noreply, %{state | yield: new_yield, thread_count: new_count + 1}}
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
    run_sub(state, message, job_id, nil)

    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_cast({:tool_continue, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:tool_continue, %Message{} = message}, %State{} = state) do
    {:noreply, do_node(message, self(), state)}
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
    message = %Message{message | retries: message.retries + 1, retry_reason: reason}

    :telemetry.execute([:agens, :job, :retry], %{}, %{
      run_id: state.run_id,
      retry: message.retries
    })

    Agens.backends(:node_retry, [state.caller, message])
    message = %Message{message | result: nil}
    GenServer.cast(self(), {{:route, message.node_id}, message})

    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_cast({:done, Message.t()}, State.t()) ::
          {:noreply, State.t()} | {:stop, :normal, State.t()}
  def handle_cast({:done, message}, %State{} = state) do
    new_count = state.thread_count - 1
    yield = Yield.thread_done(state.yield, message.thread_id)

    if new_count == 0 do
      maybe_notify_parent(state, {:done, message})

      :telemetry.execute([:agens, :job, :complete], %{}, %{run_id: state.run_id})
      state = change_status(state, :complete)
      Agens.backends(:complete, [state.caller, state.run_id])
      {:stop, :normal, %{state | thread_count: 0}}
    else
      {:noreply, %{state | yield: yield, thread_count: new_count}}
    end
  end

  @doc false
  @impl true
  @spec handle_cast({:sub_route_done, Message.t()}, State.t()) :: {:noreply, State.t()}
  def handle_cast({:sub_route_done, %Message{} = sub_message}, %State{} = state) do
    do_next(sub_message, sub_message, self(), state)
    {:noreply, state}
  end

  @doc false
  @impl true
  @spec handle_cast({:sub_node_done, Message.t(), Message.t()}, State.t()) ::
          {:noreply, State.t()}
  def handle_cast(
        {:sub_node_done, %Message{} = sub_message, %Message{} = parent_node_message},
        %State{} = state
      ) do
    parent_node = State.get_node(state, parent_node_message.node_id)

    case Agens.Serving.handle_sub(parent_node.serving, sub_message, parent_node_message) do
      {:ok, %Agens.Serving.Result{body: body, outputs: outputs, next: next}} ->
        message = %Message{
          parent_node_message
          | result: body,
            outputs: outputs,
            next: next
        }

        Agens.backends(:node_result, [state.caller, message])
        do_next(message, message, self(), state)

        {:noreply, state}

      {:error, reason} ->
        GenServer.cast(self(), {{:error, reason}, parent_node_message})
        {:noreply, state}
    end
  end

  @doc false
  @impl true
  @spec handle_cast({:end, Message.t()}, State.t()) :: {:stop, :normal, State.t()}
  def handle_cast({:end, message}, %State{} = state) do
    maybe_notify_parent(state, {:done, message})

    :telemetry.execute([:agens, :job, :end], %{}, %{run_id: state.run_id})

    state = change_status(state, :ended)
    Agens.backends(:complete, [state.caller, state.run_id])

    {:stop, :normal, state}
  end

  @doc false
  @impl true
  @spec handle_cast({{:error, any()}, Message.t()}, State.t()) :: {:stop, :shutdown, State.t()}
  def handle_cast({{:error, reason}, message}, %State{} = state) do
    :telemetry.execute([:agens, :job, :error], %{}, %{run_id: state.run_id})
    state = change_status(state, :error)
    Agens.backends(:error, [state.caller, message, reason])
    maybe_notify_parent(state, {{:error, reason}, message})

    {:stop, :shutdown, state}
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

  # OTP message pattern matching yields reference() not the opaque Task.ref()
  @dialyzer {:no_opaque, handle_info: 2}

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
    GenServer.cast(self(), {{:error, error}, message})
    {:noreply, State.remove_task(state, ref)}
  end

  # ===========================================================================
  # Terminate
  # ===========================================================================

  @doc false
  @impl true
  @spec terminate(:normal | :shutdown | {term(), list()}, State.t()) :: :ok
  def terminate({exception, _}, %State{} = state) do
    change_status(state, :error)
    Agens.backends(:error, [state.caller, terminate_message(state), exception])

    :ok
  end

  def terminate(_reason, %State{}) do
    :ok
  end

  @spec terminate_message(State.t()) :: Message.t()
  defp terminate_message(%State{tasks: tasks} = state) do
    case Map.values(tasks) do
      [%Message{} = msg | _] ->
        msg

      _ ->
        %Message{
          input: "",
          caller: state.caller,
          run_id: state.run_id,
          job_id: state.config.id,
          job_description: state.config.description
        }
    end
  end

  # ===========================================================================
  # Orchestration
  # ===========================================================================

  @doc false
  @spec do_node(Message.t(), pid(), State.t()) :: State.t()
  defp do_node(message, server_pid, %State{} = state) do
    node = State.get_node(state, message.node_id)

    cond do
      is_nil(node) ->
        GenServer.cast(server_pid, {{:error, :invalid_node}, message})

        state

      not is_nil(node.sub) ->
        message = %Message{
          build_message(message, node, state)
          | result: message.input
        }

        Agens.backends(:node_started, [state.caller, message])

        run_sub(state, message, node.sub, message)

        state

      true ->
        message = %Message{
          build_message(message, node, state)
          | serving_name: node.serving,
            node_objective: node.objective,
            tool_defs: node.tools,
            resources: node.resources,
            retries: message.retries,
            retry_reason: message.retry_reason,
            tool_calls: message.tool_calls,
            tool_results: message.tool_results
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

  @spec handle_result(
          Message.t() | {:error, atom()} | {:retry, String.t()},
          Message.t(),
          pid(),
          State.t()
        ) :: any()
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
      timeout = serving_timeout(message.serving_name)

      prepared_calls =
        Enum.map(incomplete_calls, fn %{"arguments" => arguments} = tool_call ->
          input =
            arguments
            |> Enum.map(fn %{"key" => k, "value" => v} -> {k, v} end)
            |> Enum.into(%{})

          Map.put(tool_call, "input", input)
        end)

      new_results =
        prepared_calls
        |> Task.async_stream(
          fn args ->
            tool_name = args["name"]

            :telemetry.execute([:agens, :tool, :call], %{}, %{
              job_id: job_id,
              run_id: run_id,
              name: tool_name
            })

            case Agens.Serving.call_tool(message.serving_name, args, message) do
              {:error, reason} ->
                Agens.backends(:tool_call, [
                  state.caller,
                  message,
                  %{
                    name: tool_name,
                    arguments: args["input"] || %{},
                    result: nil,
                    error: inspect(reason)
                  }
                ])

                {args["id"], {:error, reason}}

              {tool_id, result} ->
                {error, normalized_result} =
                  case result do
                    {:error, reason} -> {inspect(reason), nil}
                    other -> {nil, other}
                  end

                Agens.backends(:tool_call, [
                  state.caller,
                  message,
                  %{
                    name: tool_name,
                    arguments: args["input"] || %{},
                    result: normalized_result,
                    error: error
                  }
                ])

                {tool_id, result}
            end
          end,
          ordered: true,
          timeout: timeout,
          on_timeout: :kill_task
        )
        |> Enum.zip(prepared_calls)
        |> Enum.map(fn
          {{:ok, {tool_id, result}}, _call} -> {tool_id, result}
          {{:exit, reason}, call} -> {call["id"], {:error, reason}}
        end)
        |> Enum.into(%{})

      merged = Map.merge(message.tool_results || %{}, new_results)

      updated = %Message{message | tool_results: merged}
      GenServer.cast(server_pid, {:tool_continue, updated})
    end
  end

  defp handle_result(%Message{} = message, original, server_pid, %State{} = state) do
    Agens.backends(:node_result, [state.caller, message])
    message = %Message{message | retry_reason: nil, id: nil}
    do_next(message, original, server_pid, state)
  end

  @dialyzer {:no_match, do_next: 4}
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
                thread_id = Agens.generate_uid()
                GenServer.cast(server_pid, {:thread, thread_id})
                %Message{message | thread_id: thread_id}
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
  # Helpers
  # ===========================================================================

  @spec change_status(State.t(), atom()) :: State.t()
  defp change_status(%State{} = state, status) when is_status(status) do
    :telemetry.execute([:agens, :job, :status], %{}, %{status: status, run_id: state.run_id})
    Agens.backends(:status, [state.caller, state.run_id, status])
    State.change_status(state, status)
  end

  defp run_sub(state, message, job_id, parent_node_message) do
    spec =
      :sub
      |> Agens.backends([self(), job_id])
      |> Enum.find(&match?(%Sub{}, &1))

    if !spec do
      GenServer.cast(self(), {{:error, :job_not_loaded}, message})
    else
      spec = %{spec | parent_run_id: state.run_id, parent_node_message: parent_node_message}

      :telemetry.execute([:agens, :job, :sub], %{}, %{
        job_id: spec.config.id,
        run_id: spec.run_id,
        parent_run_id: state.run_id
      })

      start(spec.config, spec.run_id)

      run(spec.run_id, message.input,
        sub: spec,
        caller: state.caller
      )
    end
  end

  defp maybe_notify_parent(%State{sub: nil}, _msg), do: :ok

  defp maybe_notify_parent(
         %State{
           sub: %Sub{parent_run_id: parent_run_id, parent_node_message: nil}
         },
         {:done, %Message{} = sub_message}
       ) do
    run_id_to_pid(parent_run_id, :ok, fn pid ->
      GenServer.cast(pid, {:sub_route_done, sub_message})
    end)
  end

  defp maybe_notify_parent(
         %State{
           sub: %Sub{parent_run_id: parent_run_id, parent_node_message: %Message{} = parent_msg}
         },
         {:done, %Message{} = sub_message}
       ) do
    run_id_to_pid(parent_run_id, :ok, fn pid ->
      GenServer.cast(pid, {:sub_node_done, sub_message, parent_msg})
    end)
  end

  defp maybe_notify_parent(
         %State{
           sub: %Sub{parent_run_id: parent_run_id, parent_node_message: parent_msg}
         },
         {{:error, reason}, message}
       ) do
    error_message = parent_msg || message

    run_id_to_pid(parent_run_id, :ok, fn pid ->
      GenServer.cast(pid, {{:error, reason}, error_message})
    end)
  end

  @spec load_resources(Message.t(), State.t()) :: Message.t()
  defp load_resources(%Message{resources: resources} = message, _state)
       when is_nil(resources) or resources == [],
       do: message

  defp load_resources(%Message{resources: resources} = message, state) do
    timeout = serving_timeout(message.serving_name)

    loaded =
      resources
      |> Task.async_stream(
        fn resource ->
          :telemetry.execute([:agens, :resource, :load], %{}, %{
            run_id: message.run_id,
            job_id: message.job_id,
            name: resource.name
          })

          loaded =
            case Agens.Serving.load_resource(message.serving_name, resource, message) do
              {:ok, loaded} -> loaded
              {:error, _} -> resource
            end

          Agens.backends(:resource_load, [state.caller, message, loaded])

          loaded
        end,
        ordered: true,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.zip(resources)
      |> Enum.map(fn
        {{:ok, loaded}, _original} -> loaded
        {{:exit, _}, original} -> original
      end)

    %Message{message | resources: loaded}
  end

  @spec serving_timeout(atom()) :: timeout()
  defp serving_timeout(serving_name) when is_atom(serving_name) do
    case Agens.Serving.get_config(serving_name) do
      {:ok, %Agens.Serving.Config{timeout: t}} -> t
      _ -> :infinity
    end
  end

  defp incomplete_tool_calls(calls, nil), do: calls

  defp incomplete_tool_calls(calls, results) do
    Enum.reject(calls, fn call -> Map.has_key?(results, call["id"]) end)
  end

  @spec build_message(Message.t(), JobNode.t(), State.t()) :: Message.t()
  defp build_message(%Message{} = message, %JobNode{} = node, %State{} = state) do
    %Message{
      caller: state.caller,
      id: message.id || Agens.generate_uid(),
      run_id: state.run_id,
      parent_run_id: state.sub && state.sub.parent_run_id,
      job_id: state.config.id,
      job_description: state.config.description,
      agent_id: node.agent_id,
      node_id: message.node_id,
      input: message.input,
      previous_result: message.previous_result,
      thread_id: message.thread_id
    }
  end

  @spec run_id_to_pid(any(), any(), (pid() -> any())) :: any()
  defp run_id_to_pid(run_id, err, cb) do
    name = via(run_id)

    case GenServer.whereis(name) do
      nil -> err
      pid when is_pid(pid) -> cb.(pid)
    end
  end

  defp via(run_id) do
    {:via, Registry, {Agens.Registry, run_id}}
  end
end
