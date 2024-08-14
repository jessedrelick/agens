defmodule Agens.Agent do
  @moduledoc """
  The Agent module provides functions for starting, stopping and running Agents.

  `Agens.Agent` is the the primary entity powering the `Agens` library. It uses `Agens.Serving` to interact with language models through `Nx.Serving`, or with language model APIs through a `GenServer`.

  Agents can have detailed identities to further refine LM outputs, and are used together in multi-agent workflows via the `Agens.Job` module.

  Agent capabilities can be expanded even further with `Agens.Tool` modules, which are designed to handle LM functional calling. In future releases, Agents will also have access to RAG generations via knowledge base features.
  """

  defmodule Prompt do
    @moduledoc """
    The Prompt struct represents an advanced prompt for an Agent process.

    All fields are optional and will only be included in the final prompt if they are not nil.

    ## Fields
    - `:identity` - a string representing the purpose and capabilities of the agent
    - `:context` - a string representing the goal or purpose of the agent's actions
    - `:constraints` - a string listing any constraints or limitations on the agent's actions
    - `:examples` - a list of maps representing example inputs and outputs for the agent
    - `:reflection` - a string representing any additional considerations or reflection the agent should make before returning results
    """

    @derive Jason.Encoder

    @type t :: %__MODULE__{
            identity: String.t() | nil,
            context: String.t() | nil,
            constraints: String.t() | nil,
            examples: String.t() | nil,
            reflection: String.t() | nil,
            input: String.t() | nil
          }

    @enforce_keys []
    defstruct [:identity, :context, :constraints, :examples, :reflection, :input]
  end

  defmodule Config do
    @moduledoc """
    The Config struct represents the configuration for an Agent process.

    ## Fields
    - `:name` - The name of the Agent process.
    - `:serving` - The serving module or `Nx.Serving` struct for the Agent.
    - `:context` - The context or goal of the Agent. Default is nil.
    - `:knowledge` - The knowledge base or data source of the Agent. Default is nil. (Coming soon)
    - `:prompt` - The string or `Agens.Agent.Prompt` struct defining the Agent. Default is nil.
    - `:tool` - The `Agens.Tool` module for the Agent. Default is nil.
    """

    @type t :: %__MODULE__{
            name: atom(),
            serving: module() | Nx.Serving.t(),
            context: String.t() | nil,
            knowledge: module() | nil,
            prompt: Agens.Agent.Prompt.t() | String.t() | nil,
            tool: module() | nil
          }

    @enforce_keys [:name, :serving]
    defstruct [:name, :serving, :context, :knowledge, :prompt, :tool]
  end

  use GenServer

  require Logger

  alias Agens.{Message, Serving}

  @registry Application.compile_env(:agens, :registry)

  @doc """
  Starts one or more `Agens.Agent` processes
  """
  @spec start([Config.t()] | Config.t()) :: [{:ok, pid()}] | {:ok, pid()}
  def start(configs) when is_list(configs) do
    configs
    |> Enum.map(fn config ->
      start(config)
    end)
  end

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
  Stops an `Agens.Agent` process
  """
  @spec stop(atom()) :: :ok | {:error, :agent_not_found}
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
  Sends an `Agens.Message` to an `Agens.Agent`
  """
  @spec message(Message.t()) :: Message.t() | {:error, :agent_not_running}
  def message(%Message{} = message) do
    case Registry.lookup(@registry, message.agent_name) do
      [{_, {agent_pid, config}}] when is_pid(agent_pid) ->
        base = base_prompt(config, message.input)
        prompt = "<s>[INST]#{base}[/INST]"

        result =
          message
          |> Map.put(:serving_name, config.serving)
          |> Map.put(:prompt, prompt)
          |> Serving.run()

        message = Map.put(message, :result, result)
        maybe_use_tool(config.tool, message)

      [] ->
        {:error, :agent_not_running}
    end
  end

  @doc false
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: config.name)
  end

  @doc false
  @spec init(Config.t()) :: {:ok, map()}
  @impl true
  def init(_config) do
    {:ok, %{}}
  end

  @spec base_prompt(Config.t(), String.t()) :: String.t()
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

  @spec maybe_use_tool(module(), Message.t()) :: Message.t()
  defp maybe_use_tool(nil, message), do: message

  defp maybe_use_tool(tool, %Message{} = message) do
    send(
      message.parent_pid,
      {:tool_started, {message.job_name, message.step_index}, message.result}
    )

    raw =
      message.result
      |> tool.to_args()
      |> tool.execute()

    send(message.parent_pid, {:tool_raw, {message.job_name, message.step_index}, raw})

    result = tool.post(raw)

    send(message.parent_pid, {:tool_result, {message.job_name, message.step_index}, result})

    Map.put(message, :result, result)
  end

  @spec maybe_add_tool_instructions(module() | nil) :: String.t()
  defp maybe_add_tool_instructions(nil), do: ""

  defp maybe_add_tool_instructions(tool) when is_atom(tool) do
    """
    ## Tool Instructions
    #{tool.instructions()}
    """
  end
end
