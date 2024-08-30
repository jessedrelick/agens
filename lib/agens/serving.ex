defmodule Agens.Serving do
  @moduledoc """
  The Serving module provides functions for starting, stopping and running Servings.

  `Agens.Serving` accepts a `GenServer` module or `Nx.Serving` struct for processing messages.

  `Agens.Serving` is decoupled from `Agens.Agent` in order to reuse a single LM across multiple agents. In most cases, however, you will only need to start one text generation serving to be used by most, if not all, agents.

  In some cases, you may have additional servings for more specific use cases such as image generation, speech recognition, etc.

  Servings were built with the `Bumblebee` library in mind, as well as `Nx.Serving`. `GenServer` is supported for working with LM APIs instead, which may be more cost effective and easier to get started with.
  """

  defmodule Config do
    @moduledoc """
    The Config struct represents the configuration for a Serving process.

    ## Fields
    - `:name` - The name of the `Agens.Serving` process.
    - `:serving` - The `Nx.Serving` struct or `GenServer` module for the `Agens.Serving`.
    - `:prompts` - A map of custom prompt prefixes. If `nil`, default prompt prefixes will be used instead. Default prompt prefixes can also be overridden by using the `prompts` options in `Agens.Supervisor`.
    """

    @type t :: %__MODULE__{
            name: atom(),
            serving: Nx.Serving.t() | module(),
            prompts: map() | nil
          }

    @enforce_keys [:name, :serving]
    defstruct [:name, :serving, :prompts]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            registry: atom(),
            config: Config.t()
          }

    @enforce_keys [:registry, :config]
    defstruct [:registry, :config]
  end

  use GenServer

  alias Agens.Message

  @suffix "Supervisor"
  @parent "Wrapper"

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts an `Agens.Serving` process
  """
  @spec start(Config.t()) :: {:ok, pid()} | {:error, term}
  def start(%Config{} = config) do
    DynamicSupervisor.start_child(Agens, {__MODULE__, config})
  end

  @doc """
  Stops an `Agens.Serving` process
  """
  @spec stop(atom()) :: :ok | {:error, :serving_not_found}
  def stop(name) when is_atom(name) do
    name
    |> parent_name()
    |> Agens.name_to_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:stop, name})
      :ok = DynamicSupervisor.terminate_child(Agens, pid)
    end)
  end

  @doc """
  Retrieves the Serving configuration by Serving name or `pid`.
  """
  @spec get_config(atom() | pid()) :: {:ok, Config.t()} | {:error, :serving_not_found}
  def get_config(name) when is_atom(name) do
    name
    |> parent_name()
    |> Agens.name_to_pid({:error, :serving_not_found}, fn pid -> get_config(pid) end)
  end

  def get_config(pid) when is_pid(pid) do
    {:ok, GenServer.call(pid, :get_config)}
  end

  @doc """
  Executes an `Agens.Message` against an `Agens.Serving`
  """
  @spec run(Message.t()) :: String.t() | {:error, :serving_not_found}
  def run(%Message{serving_name: name} = message) when is_atom(name) do
    name
    |> parent_name()
    |> Agens.name_to_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:run, message})
    end)
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  @doc false
  @spec child_spec(Config.t()) :: Supervisor.child_spec()
  def child_spec(%Config{} = config) do
    name = parent_name(config.name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [config]},
      type: :worker,
      restart: :transient
    }
  end

  @doc false
  @spec start_link(keyword(), Config.t()) :: GenServer.on_start()
  def start_link(extra, config) do
    name = parent_name(config.name)
    opts = Keyword.put(extra, :config, config)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, State.t()} | {:stop, term(), State.t()}
  def init(opts) do
    registry = Keyword.fetch!(opts, :registry)
    prompts = Keyword.fetch!(opts, :prompts)
    config = Keyword.fetch!(opts, :config)
    config = if is_nil(config.prompts), do: Map.put(config, :prompts, prompts), else: config
    state = %State{config: config, registry: registry}
    {m, f, a} = start_function(config)

    m
    |> apply(f, a)
    |> case do
      {:ok, pid} when is_pid(pid) ->
        name = serving_name(config.name)
        {:ok, _} = Registry.register(registry, name, {pid, config})

        {:ok, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  # ===========================================================================
  # Callbacks
  # ===========================================================================

  @doc false
  @impl true
  @spec handle_call({:stop, atom()}, {pid, term}, State.t()) :: {:reply, :ok, State.t()}
  def handle_call({:stop, serving_name}, _from, state) do
    serving_name = serving_name(serving_name)
    Registry.unregister(state.registry, serving_name)
    {:reply, :ok, state}
  end

  @doc false
  @impl true
  @spec handle_call(:get_config, {pid, term}, State.t()) :: {:reply, Config.t(), State.t()}
  def handle_call(:get_config, _from, state) do
    {:reply, state.config, state}
  end

  @doc false
  @impl true
  @spec handle_call({:run, Message.t()}, {pid, term}, State.t()) ::
          {:reply, String.t(), State.t()}
  def handle_call({:run, %Message{} = message}, _, state) do
    result = do_run(state.config, message)
    {:reply, result, state}
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  @doc false
  @spec do_run(Config.t(), Message.t()) :: String.t()
  defp do_run(%Config{serving: %Nx.Serving{}}, %Message{} = message) do
    message.serving_name
    |> Nx.Serving.batched_run(message.prompt)
    |> case do
      %{results: [%{text: result}]} -> result
      result -> result
    end
  end

  defp do_run(_, %Message{} = message) do
    serving_name = serving_name(message.serving_name)
    # need to get pid?
    GenServer.call(serving_name, {:run, message})
  end

  @doc false
  @spec start_function(Config.t()) :: tuple()
  defp start_function(%Config{serving: %Nx.Serving{} = serving} = config) do
    {Nx.Serving, :start_link, [[serving: serving, name: config.name]]}
  end

  @doc false
  @spec start_function(Config.t()) :: tuple()
  # Module.concat with "Supervisor" for Nx.Serving parity
  defp start_function(%Config{serving: serving} = config) when is_atom(serving) do
    name = serving_name(config.name)
    {serving, :start_link, [[name: name, config: config]]}
  end

  @doc false
  @spec serving_name(atom) :: atom
  defp serving_name(name) when is_atom(name), do: Module.concat(name, @suffix)

  @doc false
  @spec parent_name(atom) :: atom
  defp parent_name(name) when is_atom(name), do: Module.concat(name, @parent)
end
