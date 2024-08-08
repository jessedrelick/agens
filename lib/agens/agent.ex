defmodule Agens.Agent do
  defstruct [:name, :serving, :context, :knowledge, :prompt, :tool]

  defmodule Prompt do
    @derive Jason.Encoder
    defstruct [:identity, :context, :constraints, :examples, :reflection, :input]
  end

  @registry Agens.Registry.Agents

  def start(agents) when is_list(agents) do
    agents
    |> Enum.map(fn agent ->
      start(agent)
    end)
  end

  def start(%__MODULE__{} = agent) do
    spec = %{
      id: agent.name,
      start: start_function(agent)
    }

    {:ok, pid} = DynamicSupervisor.start_child(Agens, spec)
    Registry.register(@registry, agent.name, {pid, agent})
    {:ok, pid}
  end

  def stop(name) do
    name
    |> Module.concat("Supervisor")
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :agent_not_found}

      pid ->
        DynamicSupervisor.terminate_child(Agens, pid)
    end
  end

  def message(agent_name, input) do
    case Registry.lookup(@registry, agent_name) do
      [{_, {agent_pid, agent_config}}] when is_pid(agent_pid) ->
        base = base_prompt(agent_config, input)
        prompt = "<s>[INST]#{base}[/INST]"
        serving = agent_config.serving

        %{results: [%{text: text}]} =
          cond do
            is_atom(serving) ->
              GenServer.call(agent_pid, {:run, prompt, input})

            # GenServer.call(agent_name, {:run, input})
            # apply(serving, :run, [input])

            %Nx.Serving{} = serving ->
              Nx.Serving.batched_run(agent_name, prompt)
          end

        result = maybe_use_tool(agent_config.tool, text)

        {:ok, result}

      [] ->
        {:error, :agent_not_running}
    end
  end

  defp base_prompt(%__MODULE__{prompt: %Prompt{} = prompt, tool: tool}, input) do
    """
    ## Identity
    You are a specialized agent with the following capabilities and expertise: #{prompt.identity}

    ## Context
    The purpose or goal behind your tasks are to: #{prompt.context}

    ## Constraints
    You must operate with the following constraints or limitations: #{prompt.constraints}

    ## Reflection
    You should consider the following factors before returning results: #{prompt.reflection}

    #{maybe_add_tool_instructions(tool)}

    ## Input
    The following is the actual input from the user, system or another agent: `#{input}`
    """
  end

  defp base_prompt(%__MODULE__{prompt: prompt, tool: nil}, input),
    do: "Agent: #{prompt} Input: #{input}"

  defp base_prompt(%__MODULE__{prompt: prompt, tool: tool}, input) when is_atom(tool),
    do: "Agent: #{prompt} Tool: #{tool.instructions()} Input: #{tool.pre(input)}"

  defp maybe_use_tool(nil, text), do: text

  defp maybe_use_tool(tool, text) do
    # send(parent, {:tool_started, {job_name, step_index}, text})

    raw =
      text
      |> tool.to_args()
      |> tool.execute()

    # send(parent, {:tool_raw, {job_name, step_index}, raw})

    tool.post(raw)

    # send(parent, {:tool_result, {job_name, step_index}, result})
  end

  defp maybe_add_tool_instructions(nil), do: ""

  defp maybe_add_tool_instructions(tool) when is_atom(tool) do
    """
    ## Tool Instructions
    #{tool.instructions()}
    """
  end

  defp start_function(%__MODULE__{serving: %Nx.Serving{} = serving} = agent) do
    {Nx.Serving, :start_link, [[serving: serving, name: agent.name]]}
  end

  defp start_function(%__MODULE__{serving: serving} = agent) do
    {serving, :start_link, [[name: agent.name, config: agent]]}
  end
end
