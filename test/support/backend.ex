defmodule Test.Support.Backend do
  alias Agens.Message

  @behaviour Agens.Backend

  @impl true
  def start(caller, job_id, run_id) do
    send(caller, {:job_started, job_id, run_id})

    :ok
  end

  @impl true
  def status(caller, run_id, status) do
    send(caller, {:job_status, {run_id, status}})

    :ok
  end

  @impl true
  def complete(caller, run_id) do
    send(caller, {:job_complete, run_id})

    :ok
  end

  @impl true
  def error(caller, %Message{} = message, error) do
    send(caller, {:job_error, message, error})

    :ok
  end

  @impl true
  def node_started(caller, %Message{} = message) do
    send(caller, {:node_started, message})

    :ok
  end

  @impl true
  def node_retry(caller, %Message{} = message) do
    send(caller, {:node_retry, message})

    :ok
  end

  @impl true
  def node_result(caller, %Message{} = message) do
    send(caller, {:node_result, message})

    :ok
  end

  @impl true
  def tool_call(caller, job_id, run_id, tool_name) do
    send(caller, {:tool_call, {job_id, run_id, tool_name}})

    :ok
  end

  @impl true
  def prompt(%Message{} = message) do
    send(message.caller, {:prompt, {message.system, message.user}})

    :ok
  end

  @impl true
  def yield_wait(caller, %Message{} = message, total_count, ready_count) do
    send(caller, {:yield_wait, {message, total_count, ready_count}})
  end

  @impl true
  def yield_done(caller, %Message{} = message, total_count) do
    send(caller, {:yield_done, {message, total_count}})
  end

  @impl true
  def sub(_caller, _job_id) do
    nodes = %{
      "sub_node_0" => %Agens.Job.Node{
        serving: :test_serving,
        agent: :sub_final_agent
      }
    }

    %Agens.Job.Sub{
      config: %Agens.Job.Config{id: "sub", nodes: nodes},
      run_id: "sub_run_id",
      first_node_id: "sub_node_0"
    }
  end
end
