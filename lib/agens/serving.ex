defmodule Agens.Serving do
  defmodule Config do
    defstruct [:name, :serving]
  end

  require Logger

  alias Agens.Message

  @registry Application.compile_env(:agens, :registry)

  def start(%Config{} = config) do
    spec = %{
      id: config.name,
      start: start_function(config)
    }

    pid =
      Agens
      |> DynamicSupervisor.start_child(spec)
      |> case do
        {:ok, pid} ->
          pid

        {:error, {:already_started, pid}} ->
          Logger.warning("Serving #{config.name} already started")
          pid
      end

    Registry.register(@registry, config.name, {pid, config})
    {:ok, pid}
  end

  def stop(serving_name) do
    serving_name
    |> Module.concat("Supervisor")
    |> Process.whereis()
    |> case do
      nil ->
        {:error, :agent_not_found}

      pid ->
        :ok = DynamicSupervisor.terminate_child(Agens, pid)
        Registry.unregister(@registry, serving_name)
    end
  end

  def run(%Message{} = message) do
    case Registry.lookup(@registry, message.serving_name) do
      [{_, {serving_pid, config}}] when is_pid(serving_pid) ->
        %{results: [%{text: text}]} = do_run({serving_pid, config}, message)

        text

      [] ->
        {:error, :serving_not_running}
    end
  end

  defp do_run({_, %Config{serving: %Nx.Serving{}}}, %Message{} = message) do
    Nx.Serving.batched_run(message.serving_name, message.prompt)
  end

  defp do_run({serving_pid, _}, %Message{} = message) do
    # GenServer.call(serving_name, {:run, input})
    GenServer.call(serving_pid, {:run, message.prompt, message.input})
  end

  defp start_function(%Config{serving: %Nx.Serving{} = serving} = config) do
    {Nx.Serving, :start_link, [[serving: serving, name: config.name]]}
  end

  # Module.concat with "Supervisor" for Nx.Serving parity
  defp start_function(%Config{serving: serving} = config) when is_atom(serving) do
    name = Module.concat(config.name, "Supervisor")
    {serving, :start_link, [[name: name, config: config]]}
  end
end
