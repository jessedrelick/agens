defmodule Agens.Serving do
  defmodule Config do
    defstruct [:name, :serving]
  end

  require Logger

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

  def run(serving_name, prompt, input) do
    case Registry.lookup(@registry, serving_name) do
      [{_, {serving_pid, config}}] when is_pid(serving_pid) ->
        %{results: [%{text: text}]} = do_run({serving_pid, config}, prompt, input)

        text

      [] ->
        {:error, :serving_not_running}
    end
  end

  defp do_run({_, %Config{serving: %Nx.Serving{}} = config}, prompt, _input) do
    Nx.Serving.batched_run(config.name, prompt)
  end

  defp do_run({serving_pid, _}, prompt, input) do
    # GenServer.call(serving_name, {:run, input})
    GenServer.call(serving_pid, {:run, prompt, input})
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
