defmodule AgensDemo.FileBackend do
  @behaviour Agens.Backend

  alias Agens.Message
  alias AgensDemo.History

  @impl true
  def start(_caller, _job_id, _run_id), do: :ok

  @impl true
  def status(_caller, _run_id, _status), do: :ok

  @impl true
  def complete(_caller, _run_id), do: :ok

  @impl true
  def error(_caller, %Message{}, _error), do: :ok

  @impl true
  def node_started(_caller, %Message{}), do: :ok

  @impl true
  def node_retry(_caller, %Message{} = message) do
    History.write(message)
    :ok
  end

  @impl true
  def node_result(_caller, %Message{} = message) do
    History.write(message)
    :ok
  end

  @impl true
  def tool_call(_caller, _job_id, _run_id, _tool_name), do: :ok

  @impl true
  def prompt(%Message{}), do: :ok

  @impl true
  def yield_wait(_caller, %Message{}, _total, _ready), do: :ok

  @impl true
  def yield_done(_caller, %Message{}, _total), do: :ok

  @impl true
  def sub(_caller, _job_id), do: nil
end
