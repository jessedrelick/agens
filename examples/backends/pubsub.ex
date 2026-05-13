defmodule AgensDemo.PubSubBackend do
  @behaviour Agens.Backend

  alias Agens.Message

  @pubsub AgensDemo.PubSub
  @topic_prefix "agens"

  @impl true
  def start(_caller, _job_id, run_id) do
    broadcast(run_id, {:job_started, run_id})
  end

  @impl true
  def status(_caller, run_id, status) do
    broadcast(run_id, {:job_status, run_id, status})
  end

  @impl true
  def complete(_caller, run_id) do
    broadcast(run_id, {:job_complete, run_id})
  end

  @impl true
  def error(_caller, %Message{run_id: run_id} = message, error) do
    broadcast(run_id, {:job_error, message, error})
  end

  @impl true
  def node_started(_caller, %Message{run_id: run_id} = message) do
    broadcast(run_id, {:node_started, message})
  end

  @impl true
  def node_retry(_caller, %Message{run_id: run_id} = message) do
    broadcast(run_id, {:node_retry, message})
  end

  @impl true
  def node_result(_caller, %Message{run_id: run_id} = message) do
    broadcast(run_id, {:node_result, message})
  end

  @impl true
  def tool_call(_caller, %Message{run_id: run_id} = message, %{} = tool_call) do
    broadcast(run_id, {:tool_call, message, tool_call})
  end

  @impl true
  def resource_load(_caller, %Message{run_id: run_id} = message, resource) do
    broadcast(run_id, {:resource_load, message, resource})
  end

  @impl true
  def prompt(%Message{}), do: :ok

  @impl true
  def yield_wait(_caller, %Message{run_id: run_id} = message, total, ready) do
    broadcast(run_id, {:yield_wait, message, total, ready})
  end

  @impl true
  def yield_done(_caller, %Message{run_id: run_id} = message, total) do
    broadcast(run_id, {:yield_done, message, total})
  end

  @impl true
  def sub(_caller, _job_id), do: nil

  defp broadcast(run_id, event) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}:#{run_id}", event)
  end
end
