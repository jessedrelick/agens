defmodule Agens.Backend.Log do
  @moduledoc false

  require Logger

  alias Agens.Message

  @behaviour Agens.Backend

  @name "Log"

  @impl true
  def run(_caller, job_id, run_id) do
    Logger.info("[Agens: #{@name}] Running job: #{job_id} run_id: #{run_id}")

    :ok
  end

  @impl true
  def status(_caller, run_id, status) do
    Logger.info("[Agens: #{@name}] Run `#{run_id}` status change: #{inspect(status)}")

    :ok
  end

  @impl true
  def complete(_caller, run_id) do
    Logger.info("[Agens: #{@name}] Run `#{run_id}` complete")

    :ok
  end

  @impl true
  def ended(_caller, run_id) do
    Logger.info("[Agens: #{@name}] Run `#{run_id}` ended")

    :ok
  end

  @impl true
  def error(_caller, %Message{} = message, error) do
    Logger.error(
      "[Agens: #{@name}] Error on run `#{message.run_id}` node: #{message.node_id} error: #{inspect(error)}"
    )

    :ok
  end

  @impl true
  def node_started(_caller, %Message{} = message) do
    Logger.info(
      "[Agens: #{@name}] Starting node: #{message.node_id} run_id: #{message.run_id} thread: #{message.thread_id}"
    )

    :ok
  end

  @impl true
  def node_retry(_caller, %Message{} = message) do
    Logger.info(
      "[Agens: #{@name}] Retrying node: #{message.node_id} run_id: #{message.run_id} thread: #{message.thread_id}"
    )

    :ok
  end

  @impl true
  def node_result(_caller, %Message{} = message) do
    Logger.info(
      "[Agens: #{@name}] Completed node: #{message.node_id} run_id: #{message.run_id} thread: #{message.thread_id}"
    )

    :ok
  end

  @impl true
  def tool_call(_caller, %Message{} = message, %{tool: %{name: tool_name}, error: error}) do
    Logger.info(
      "[Agens: #{@name}] Tool call: #{tool_name} run_id: #{message.run_id} node: #{message.node_id} error: #{inspect(error)}"
    )

    :ok
  end

  @impl true
  def resource_load(_caller, %Message{} = message, %{resource: resource, error: error}) do
    Logger.info(
      "[Agens: #{@name}] Resource load: #{resource.name} run_id: #{message.run_id} node: #{message.node_id} error: #{inspect(error)}"
    )

    :ok
  end

  @impl true
  def prompt(%Message{}), do: :ok

  @impl true
  def yield_wait(_caller, _message, total_count, ready_count) do
    Logger.info("[Agens: #{@name}] Yield wait: #{ready_count}/#{total_count}")

    :ok
  end

  @impl true
  def yield_done(_caller, _message, total_count) do
    Logger.info("[Agens: #{@name}] Yield done: #{total_count} total")

    :ok
  end

  @impl true
  def sub(_job_id), do: nil
end
