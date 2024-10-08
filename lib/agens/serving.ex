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
    - `:name` - The unique name for the Serving process.
    - `:serving` - The `Nx.Serving` struct or `GenServer` module for the `Agens.Serving`.
    - `:prefixes` - An `Agens.Prefixes` struct of custom prompt prefixes. If `nil`, default prompt prefixes will be used instead. Default prompt prefixes can also be overridden by using the `prefixes` options in `Agens.Supervisor`.
    - `:finalize` - A function that accepts the prepared prompt (including any applied prefixes) and returns a modified version of the prompt. Useful for wrapping the prompt or applying final processing before sending to the LM for inference. If `nil`, the prepared prompt will be used as-is.
    - `:args` - Additional arguments to be passed to the `Nx.Serving` or `GenServer` module. See the [Nx.Serving](https://hexdocs.pm/nx/Nx.Serving.html) or [GenServer](https://hexdocs.pm/elixir/GenServer.html) documentation for more information.
    """

    @type t :: %__MODULE__{
            name: atom(),
            serving: Nx.Serving.t() | module(),
            args: keyword(),
            prefixes: Agens.Prefixes.t() | nil,
            finalize: (String.t() -> String.t()) | nil
          }

    @enforce_keys [:name, :serving]
    defstruct [:name, :serving, :prefixes, :finalize, args: []]
  end

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            config: Config.t()
          }

    @enforce_keys [:config]
    defstruct [:config]
  end

  use GenServer

  alias Agens.Message

  @suffix "Serving"

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
    |> Agens.name_to_pid({:error, :serving_not_found}, fn pid ->
      :ok = DynamicSupervisor.terminate_child(Agens, pid)
    end)
  end

  @doc """
  Retrieves the Serving configuration by Serving name or `pid`.
  """
  @spec get_config(atom() | pid()) :: {:ok, Config.t()} | {:error, :serving_not_found}
  def get_config(name) when is_atom(name) do
    name
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
    |> Agens.name_to_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:run, message})
    end)
  end

  @doc false
  @spec finalize(atom() | pid(), String.t()) :: {:ok, String.t()} | {:error, :serving_not_found}
  def finalize(name, prompt) when is_atom(name) do
    name
    |> Agens.name_to_pid({:error, :serving_not_found}, fn pid ->
      finalize(pid, prompt)
    end)
  end

  def finalize(pid, prompt) when is_pid(pid) do
    {:ok, GenServer.call(pid, {:finalize, prompt})}
  end

  # ===========================================================================
  # Setup
  # ===========================================================================

  @doc false
  @spec child_spec(Config.t()) :: Supervisor.child_spec()
  def child_spec(%Config{} = config) do
    %{
      id: config.name,
      start: {__MODULE__, :start_link, [config]}
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
  @spec init(keyword()) :: {:ok, State.t()} | {:stop, term(), State.t()}
  def init(opts) do
    prefixes = Keyword.fetch!(opts, :prefixes)
    config = Keyword.fetch!(opts, :config)
    config = if is_nil(config.prefixes), do: Map.put(config, :prefixes, prefixes), else: config
    state = %State{config: config}

    config
    |> start_serving()
    |> case do
      {:ok, pid} when is_pid(pid) ->
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

  @doc false
  @impl true
  @spec handle_call({:finalize, String.t()}, {pid, term}, State.t()) ::
          {:reply, String.t(), State.t()}
  def handle_call({:finalize, prompt}, _, %State{config: %Config{finalize: finalize}} = state) do
    final =
      case finalize do
        fun when is_function(fun, 1) -> fun.(prompt)
        _ -> prompt
      end

    {:reply, final, state}
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  @doc false
  @spec do_run(Config.t(), Message.t()) :: String.t()
  defp do_run(%Config{serving: %Nx.Serving{}}, %Message{} = message) do
    message.serving_name
    |> serving_name()
    |> Nx.Serving.batched_run(message.prompt)
    |> case do
      %{results: [%{text: result}]} -> result
      result -> result
    end
  end

  defp do_run(_, %Message{} = message) do
    message.serving_name
    |> serving_name()
    |> GenServer.call({:run, message})
  end

  @doc false
  @spec start_serving(Config.t()) :: tuple()
  defp start_serving(%Config{serving: %Nx.Serving{} = serving, args: args} = config) do
    name = serving_name(config.name)

    opts =
      args
      |> Keyword.put(:serving, serving)
      |> Keyword.put(:name, name)

    Nx.Serving.start_link(opts)
  end

  defp start_serving(%Config{serving: serving, args: args} = config) when is_atom(serving) do
    name = serving_name(config.name)
    opts = Keyword.put(args, :name, name)

    GenServer.start_link(serving, config, opts)
  end

  @doc false
  @spec serving_name(atom) :: atom
  defp serving_name(name) when is_atom(name), do: Module.concat(name, @suffix)
end
