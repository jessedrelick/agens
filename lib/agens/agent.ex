defmodule Agens.Agent do
  @moduledoc """
  The Agent module provides struct and function definitions for an Agent process.

  ## Example
      # First, add the Agens supervisor to your application supervision tree
      Supervisor.start_link(
        [
          {Agens.Supervisor, name: Agens.Supervisor}
        ],
        strategy: :one_for_one
      )

      # Ensure the test registry is running (see `Test.Support.AgentCase`)
      iex> registry = Application.get_env(:agens, :registry)
      iex> Process.whereis(registry) |> is_pid()
      true
      iex> serving_config = %Agens.Serving.Config{
      ...>   name: :test_serving,
      ...>   serving: Test.Support.Serving.get(false)
      ...> }
      %Agens.Serving.Config{name: :test_serving, serving: serving_config.serving}
      iex> {:ok, pid} = Agens.Serving.start(serving_config)
      iex> is_pid(pid)
      true
      # Start an Agent with a name and serving module
      iex> {:ok, pid} = %Agens.Agent.Config{
      ...>   name: :test_agent,
      ...>   serving: :test_serving
      ...> }
      ...> |> Agens.Agent.start()
      iex> is_pid(pid)
      true
      # Send a message to the Agent by agent name
      iex> Agens.Agent.message(:test_agent, "hello")
      {:ok, "sent 'hello' to: test_agent"}

  """

  defmodule Prompt do
    @moduledoc """
    The Prompt struct represents a prompt for an Agent process.
    """

    @derive Jason.Encoder

    @type t :: %__MODULE__{
            identity: String.t(),
            context: String.t(),
            constraints: String.t(),
            examples: String.t(),
            reflection: String.t(),
            input: String.t()
          }

    @enforce_keys []
    defstruct [:identity, :context, :constraints, :examples, :reflection, :input]
  end

  defmodule Config do
    @moduledoc """
    The `Config` struct represents an Agent process.

    ## Fields
    - `:name` - The name of the Agent process.
    - `:serving` - The serving module or Nx.Serving struct for the Agent. Default is nil.
    - `:context` - The context or goal of the Agent. Default is nil.
    - `:knowledge` - The knowledge base or data source of the Agent. Default is nil.
    - `:prompt` - The `Prompt` struct for the Agent. Default is nil.
    - `:tool` - The tool module for the Agent. Default is nil.
    """

    @enforce_keys [:name, :serving]
    @type t :: %__MODULE__{
            name: atom(),
            serving: module() | Nx.Serving.t(),
            context: String.t() | nil,
            knowledge: module() | nil,
            prompt: Agens.Agent.Prompt.t() | String.t() | nil,
            tool: module() | nil
          }
    defstruct [:name, :serving, :context, :knowledge, :prompt, :tool]
  end

  use GenServer

  require Logger

  alias Agens.Serving

  @registry Application.compile_env(:agens, :registry)

  @doc """
  Starts one or more agents
  """
  @spec start([Config.t()] | Config.t()) :: [pid()] | {:ok, pid()}
  def start(configs) when is_list(configs) do
    configs
    |> Enum.map(fn config ->
      start(config)
    end)
  end

  @spec start(Config.t()) :: {:ok, pid()}
  @type start_result :: {:ok, pid()}
  def start(%Config{} = config) do
    spec = %{
      id: config.name,
      start: {__MODULE__, :start_link, [config]}
      # type: :worker,
      # restart: :transient
    }

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

    Registry.register(@registry, config.name, {pid, config})
    {:ok, pid}
  end

  @doc """
  Stops an agent
  """
  @spec stop(atom()) :: :ok | {:error, :agent_not_found}
  @type stop_result :: :ok | {:error, :agent_not_found}
  def stop(agent_name) do
    agent_name
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :agent_not_found}

      pid ->
        :ok = DynamicSupervisor.terminate_child(Agens, pid)
        Registry.unregister(@registry, agent_name)
    end
  end

  @doc """
  Sends a message to an agent
  """
  @spec message(atom(), String.t()) :: {:ok, String.t()} | {:error, :agent_not_running}
  @type message_result :: {:ok, String.t()} | {:error, :agent_not_running}
  def message(agent_name, input) do
    case Registry.lookup(@registry, agent_name) do
      [{_, {agent_pid, config}}] when is_pid(agent_pid) ->
        base = base_prompt(config, input)
        prompt = "<s>[INST]#{base}[/INST]"
        text = Serving.run(config.serving, prompt, input)
        maybe_use_tool(config.tool, text)

      [] ->
        {:error, :agent_not_running}
    end
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config.name)
  end

  @impl true
  def init(_config) do
    {:ok, %{}}
  end

  defp base_prompt(%Config{prompt: %Prompt{} = prompt, tool: tool}, input) do
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

  defp base_prompt(%Config{prompt: prompt, tool: nil}, input),
    do: "Agent: #{prompt} Input: #{input}"

  defp base_prompt(%Config{prompt: prompt, tool: tool}, input) when is_atom(tool),
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
end
