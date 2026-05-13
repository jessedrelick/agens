defmodule Test.Support.ErrorSubBackend do
  @behaviour Agens.Backend

  alias Test.Support.Backend

  @impl true
  def start(caller, job_id, run_id), do: Backend.start(caller, job_id, run_id)

  @impl true
  def status(caller, run_id, status), do: Backend.status(caller, run_id, status)

  @impl true
  def complete(caller, run_id), do: Backend.complete(caller, run_id)

  @impl true
  def error(caller, message, error), do: Backend.error(caller, message, error)

  @impl true
  def node_started(caller, message), do: Backend.node_started(caller, message)

  @impl true
  def node_retry(caller, message), do: Backend.node_retry(caller, message)

  @impl true
  def node_result(caller, message), do: Backend.node_result(caller, message)

  @impl true
  def tool_call(caller, message, tool_call),
    do: Backend.tool_call(caller, message, tool_call)

  @impl true
  def resource_load(caller, message, resource),
    do: Backend.resource_load(caller, message, resource)

  @impl true
  def prompt(message), do: Backend.prompt(message)

  @impl true
  def yield_wait(caller, message, total_count, ready_count),
    do: Backend.yield_wait(caller, message, total_count, ready_count)

  @impl true
  def yield_done(caller, message, total_count),
    do: Backend.yield_done(caller, message, total_count)

  @impl true
  def sub(_caller, _job_id) do
    nodes = %{
      "sub_node_0" => %Agens.Job.Node{
        serving: :test_serving,
        agent_id: :sub_error_agent
      }
    }

    %Agens.Job.Sub{
      config: %Agens.Job.Config{id: "sub_error", nodes: nodes, starting_node_id: "sub_node_0"},
      run_id: "sub_error_run_id"
    }
  end
end
