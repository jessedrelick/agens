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

  @suffix "Supervisor"
  @parent "Wrapper"

  @doc """
  Starts an `Agens.Serving` process
  """
  @spec start(Config.t()) :: {:ok, pid()}
  def start(%Config{} = config) do
    DynamicSupervisor.start_child(Agens, {__MODULE__, config})
  end

  def child_spec(config) do
    name = parent_name(config.name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [config]}
    }
  end

  def start_link(extra, config) do
    name = parent_name(config.name)
    opts = Keyword.put(extra, :config, config)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def init(opts) do
    registry = Keyword.fetch!(opts, :registry)
    prompts = Keyword.fetch!(opts, :prompts)
    config = Keyword.fetch!(opts, :config)
    state = %{config: config, registry: registry, prompts: prompts}
    {m, f, a} = start_function(config)

    m
    |> apply(f, a)
    |> case do
      {:ok, pid} when is_pid(pid) ->
        name = serving_name(config.name)
        Registry.register(registry, name, {pid, config})
        {:ok, state}

      {:error, {:already_started, pid}} when is_pid(pid) ->
        {:ok, state}

      {:error, reason} ->
        {:stop, reason, state}
    end
  end

  @doc """
  Stops an `Agens.Serving` process
  """
  @spec stop(atom()) :: :ok | {:error, :serving_not_found}
  def stop(name) do
    name
    |> parent_name()
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :serving_not_found}

      pid when is_pid(pid) ->
        GenServer.call(pid, {:stop, name})
        :ok = DynamicSupervisor.terminate_child(Agens, pid)
    end
  end

  @doc """
  Executes an `Agens.Message` against an `Agens.Serving`
  """
  @spec run(Message.t()) :: String.t() | {:error, :serving_not_running}
  def run(%Message{} = message) do
    message.serving_name
    |> parent_name()
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :serving_not_found}

      pid when is_pid(pid) ->
        GenServer.call(pid, {:run, message})
    end
  end

  def handle_call({:stop, serving_name}, _from, state) do
    serving_name = serving_name(serving_name)
    Registry.unregister(state.registry, serving_name)
    {:reply, :ok, state}
  end

  def handle_call({:run, %Message{} = message}, _, %{registry: registry} = state) do
    result =
      with {:ok, agent_config} <- get_agent_config(registry, message.agent_name),
           serving_name <- serving_name(message.serving_name),
           {:ok, {serving_pid, serving_config}} <- get_serving_config(registry, serving_name) do
        base = Message.build_prompt(agent_config, message, state.prompts)
        prompt = "<s>[INST]#{base}[/INST]"
        message = Map.put(message, :prompt, prompt)

        result = do_run({serving_pid, serving_config}, message)

        message = Map.put(message, :result, result)
        tool = if agent_config, do: agent_config.tool, else: nil
        Message.maybe_use_tool(message, tool)
      else
        {:error, reason} -> {:error, reason}
      end

    {:reply, result, state}
  end

  defp get_agent_config(_registry, nil), do: {:ok, nil}

  defp get_agent_config(registry, agent_name) do
    case Registry.lookup(registry, agent_name) do
      [{_, {agent_pid, agent_config}}] when is_pid(agent_pid) ->
        {:ok, agent_config}

      [] ->
        {:error, :agent_not_running}
    end
  end

  defp get_serving_config(registry, serving_name) do
    case Registry.lookup(registry, serving_name) do
      [{_, {serving_pid, serving_config}}] when is_pid(serving_pid) ->
        {:ok, {serving_pid, serving_config}}

      [] ->
        {:error, :serving_not_running}
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
    name = serving_name(config.name)
    {serving, :start_link, [[name: name, config: config]]}
  end

  defp serving_name(name) when is_atom(name), do: Module.concat(name, @suffix)

  defp parent_name(name) when is_atom(name), do: Module.concat(name, @parent)
end
