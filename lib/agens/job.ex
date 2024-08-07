defmodule Agens.Job do
  use GenServer

  defmodule Config do
    defstruct [:name, :objective, :steps]
  end

  defmodule Step do
    defstruct [:agent, :prompt, :conditions, :tool]
  end

  defmodule State do
    defstruct [:status, :step_index, :config, :parent]
  end

  def start(pid, input) when is_pid(pid) do
    GenServer.call(pid, {:start, input})
  end

  def start(name, input) when is_atom(name) do
    name
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :job_not_found}

      pid when is_pid(pid) ->
        start(pid, input)
    end
  end

  def get_config(pid) when is_pid(pid), do: GenServer.call(pid, :get_config)

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
  def handle_cast(:end, %State{config: %Config{name: name}} = state) do
    new_state = %State{state | status: :complete}
    send(state.parent, {:job_ended, name, :complete})
    {:stop, :complete, new_state}
  end

  @impl true
  def terminate({error, _}, %State{config: %{name: name}} = state) do
    send(state.parent, {:job_ended, name, {:error, error}})
    :ok
  end

  defp do_step(input, %State{config: config} = state) do
    %Step{tool: tool} = step = Enum.at(config.steps, state.step_index)

    msg = build_msg(step, input)

    send(state.parent, {:step_started, config.name, state.step_index, input})
    %{results: [%{text: text}]} = Agens.message(step.agent, msg)
    send(state.parent, {:step_result, config.name, state.step_index, text})

    text = use_tool(tool, text, state)

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

  defp build_msg(%Step{tool: nil, prompt: prompt}, input), do: "#{prompt}#{input}"

  defp build_msg(%Step{tool: tool, prompt: prompt}, input) do
    "#{prompt} #{tool.instructions()} #{tool.pre(input)}"
  end

  defp use_tool(nil, text, _state), do: text

  defp use_tool(tool, text, state) do
    send(state.parent, {:tool_started, state.config.name, state.step_index, text})

    raw =
      text
      |> tool.to_args()
      |> tool.execute()

    send(state.parent, {:tool_result, state.config.name, state.step_index, raw})

    tool.post(raw)
  end
end
