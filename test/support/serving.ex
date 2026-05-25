defmodule Test.Support.Serving do
  use Agens.Serving

  alias Agens.{Message, Resource}
  alias Test.Support.{Resources, Tools}

  @impl true
  def start(state) do
    {:ok, state}
  end

  @impl true
  def load_resource(_state, %Resource{uri: uri} = resource, _message) do
    %Resource{resource | content: Resources.resource_content(uri)}
  end

  @impl true
  def tool_call(_state, %{"name" => "outer_error_tool"}, _message), do: {:error, :outer_failed}

  def tool_call(_state, %{"name" => "inner_error_tool", "id" => id}, _message),
    do: {id, {:error, :inner_failed}}

  def tool_call(_state, tool_call, _message), do: Tools.tool_exec(tool_call)

  @impl true
  def handle_message(_state, %Message{} = message, _schema) do
    Process.sleep(10)
    {:ok, map_input(message.agent_id, message.previous_result || message.input)}
  end

  @impl true
  def handle_result({:ok, {:error, err}}, _state, _msg) do
    {:error, err}
  end

  @impl true
  def handle_result({:ok, {:retry, reason}}, _state, _msg) do
    {:retry, reason}
  end

  @impl true
  def handle_result({:ok, %Result{} = result}, _state, _msg) do
    {:ok, result}
  end

  # ===========================================================================
  # Private
  # ===========================================================================

  defp map_input("first_agent", "invalid next") do
    %Result{
      body: "invalid next test",
      next: "invalid next node"
    }
  end

  defp map_input("first_agent", input) do
    body =
      %{
        "D" => "C",
        "E" => "D",
        "F" => "E"
      }
      |> Map.get(input, "ERROR")

    %Result{
      body: body,
      next: [{:route, "node_10", 1}]
    }
  end

  defp map_input("second_agent", input) do
    body =
      %{
        "C" => "E",
        "D" => "F",
        "E" => "G"
      }
      |> Map.get(input, "ERROR")

    %Result{
      body: body,
      next: [{:route, "node_20", 1}]
    }
  end

  defp map_input("verifier_agent", "G") do
    %Result{
      body: "TRUE",
      next: [:end]
    }
  end

  defp map_input("verifier_agent", input) do
    %Result{
      body: input,
      next: [{:route, "node_0", 1}]
    }
  end

  defp map_input("parallel_agent", input) do
    %Result{
      body: input,
      next: [{:route, "node_10", 4}]
    }
  end

  defp map_input("retry_agent", "error") do
    {:retry, "validation error"}
  end

  defp map_input("retry_agent", "explicit") do
    %Result{
      body: "explicit retry",
      next: [:retry]
    }
  end

  defp map_input("retry_agent", "explicit_with_reason") do
    %Result{
      body: "explicit retry with reason",
      next: [{:retry, "LLM provided reason"}]
    }
  end

  defp map_input("retry_agent", "fatal") do
    {:error, :fatal_error}
  end

  defp map_input("resource_agent", _input) do
    %Result{
      body: "resource agent result",
      next: [:end]
    }
  end

  defp map_input("tool_agent", input) do
    tool_call = Tools.tool_call("tool_call_id")

    %Result{
      body: input,
      next: [],
      tool_calls: [tool_call]
    }
  end

  defp map_input("tool_error_agent", input) do
    %Result{
      body: input,
      next: [],
      tool_calls: [
        %{"id" => "outer_id", "name" => "outer_error_tool", "arguments" => []},
        %{"id" => "inner_id", "name" => "inner_error_tool", "arguments" => []}
      ]
    }
  end

  defp map_input("error_agent", _input) do
    raise "unexpected error test"
  end

  defp map_input("end_agent", _input) do
    %Result{
      body: "end",
      next: [:end]
    }
  end

  defp map_input("split_agent", input) do
    %Result{
      body: input,
      next: [{:route, "node_10", 4}]
    }
  end

  defp map_input("concurrent_agent", input) do
    %Result{
      body: input,
      next: [{:yield, "node_20"}]
    }
  end

  defp map_input("yield_agent", input) do
    %Result{
      body: input
    }
  end

  defp map_input("sub_agent", input) do
    %Result{
      body: input,
      next: [{:sub, "sub_job"}]
    }
  end

  defp map_input("sub_error_agent", _input) do
    {:error, :sub_fatal_error}
  end

  defp map_input(agent, input) do
    %Result{
      body: "sent '#{input}' to: #{agent}",
      next: []
    }
  end
end
