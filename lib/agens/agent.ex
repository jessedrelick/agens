defmodule Agens.Agent do
  @moduledoc """
  The Agent module provides functions for starting, stopping and running Agents.

  `Agens.Agent` is the the primary entity powering `Agens`. It uses `Agens.Serving` to interact with language models through `Nx.Serving`, or with language model APIs through a `GenServer`.

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
    - `:examples` - a list of example inputs and outputs for the agent
    - `:reflection` - a string representing any additional considerations or reflection the agent should make before returning results
    """

    @type t :: %__MODULE__{
            identity: String.t() | nil,
            context: String.t() | nil,
            constraints: String.t() | nil,
            examples: String.t() | nil,
            reflection: String.t() | nil
          }

    @enforce_keys []
    defstruct [:identity, :context, :constraints, :examples, :reflection]
  end

  defmodule Config do
    @moduledoc """
    The Config struct represents the configuration for an Agent process.

    ## Fields
    - `:name` - The name of the Agent process.
    - `:serving` - The serving module or `Nx.Serving` struct for the Agent.
    - `:knowledge` - The knowledge base or data source of the Agent. Default is nil. (Coming soon)
    - `:prompt` - The string or `Agens.Agent.Prompt` struct defining the Agent. Default is nil.
    - `:tool` - The module implementing the `Agens.Tool` behaviour for the Agent. Default is nil.
    """

    @type t :: %__MODULE__{
            name: atom(),
            serving: module() | Nx.Serving.t(),
            knowledge: module() | nil,
            prompt: Agens.Agent.Prompt.t() | String.t() | nil,
            tool: module() | nil
          }

    @enforce_keys [:name, :serving]
    defstruct [:name, :serving, :knowledge, :prompt, :tool]
  end

  use GenServer

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

    Agens
    |> DynamicSupervisor.start_child(spec)
    |> case do
      {:ok, pid} when is_pid(pid) ->
        Registry.register(@registry, config.name, {pid, config})
        {:ok, pid}

      {:error, {:already_started, pid}} = err when is_pid(pid) ->
        err
    end
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
end
