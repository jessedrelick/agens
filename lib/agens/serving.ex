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
    """

    @type t :: %__MODULE__{
            name: atom(),
            serving: Nx.Serving.t() | module()
          }

    @enforce_keys [:name, :serving]
    defstruct [:name, :serving]
  end

  use GenServer

  alias Agens.Message

  @doc """
  Starts an `Agens.Serving` process
  """
  @spec start(Config.t()) :: {:ok, pid()}
  def start(%Config{} = config) do
    DynamicSupervisor.start_child(Agens, {__MODULE__, config})
  end

  def child_spec(config) do
    %{
      id: Module.concat(config.name, "Wrapper"),
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def start_link(extra, config) do
    GenServer.start_link(__MODULE__, [config, extra], name: config.name)
  end

  def init([config, opts]) do
    registry = Keyword.fetch!(opts, :registry)
    {:ok, %{config: config, registry: registry}, {:continue, :start_serving}}
  end

  def handle_continue(:start_serving, state) do
    {m, f, a} = start_function(state.config)
    m
    |> apply(f, a)
    |> case do
      {:ok, pid} when is_pid(pid) ->
        Registry.register(state.registry, state.config.name, {pid, state.config})
        {:noreply, state}

      {:error, {:already_started, pid}} when is_pid(pid) ->
        {:noreply, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @doc """
  Stops an `Agens.Serving` process
  """
  @spec stop(atom()) :: :ok | {:error, :serving_not_found}
  def stop(serving_name) do
    GenServer.call(serving_name, {:stop, serving_name})
  end

  @doc """
  Executes an `Agens.Message` against an `Agens.Serving`
  """
  @spec run(Message.t()) :: String.t() | {:error, :serving_not_running}
  def run(%Message{} = message) do
    GenServer.call(message.serving_name, {:run, message})
  end

  def handle_call({:run, %Message{} = message}, _, state) do
    state.registry
    |> Registry.lookup(message.serving_name)
    |> case do
      [{_, {serving_pid, config}}] when is_pid(serving_pid) ->
        {:reply, do_run({serving_pid, config}, message), state}

      [] ->
        {:reply, {:error, :serving_not_running}, state}
    end
  end

  def handle_call({:stop, serving_name}, _from, state) do
    serving_name
    |> Module.concat("Supervisor")
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :serving_not_found}

      pid ->
        :ok = DynamicSupervisor.terminate_child(Agens, pid)
        Registry.unregister(state.registry, serving_name)
    end
  end

  @spec do_run({pid(), Config.t()}, Message.t()) :: String.t()
  defp do_run({_, %Config{serving: %Nx.Serving{}}}, %Message{} = message) do
    message.serving_name
    |> Nx.Serving.batched_run(message.prompt)
    |> case do
      %{results: [%{text: result}]} -> result
      result -> result
    end
  end

  defp do_run({serving_pid, _}, %Message{} = message) do
    # GenServer.call(serving_name, {:run, message})
    GenServer.call(serving_pid, {:run, message})
  end

  @spec start_function(Config.t()) :: tuple()
  defp start_function(%Config{serving: %Nx.Serving{} = serving} = config) do
    {Nx.Serving, :start_link, [[serving: serving, name: config.name]]}
  end

  # Module.concat with "Supervisor" for Nx.Serving parity
  defp start_function(%Config{serving: serving} = config) when is_atom(serving) do
    name = Module.concat(config.name, "Supervisor")
    {serving, :start_link, [[name: name, config: config]]}
  end
end
