defmodule Agens.ServingTest do
  use ExUnit.Case, async: false

  alias Agens.{Message, Prefixes, Serving}
  alias Agens.Serving.Result

  defp msg(), do: %Message{input: "test"}

  def forward_telemetry(_event, _measurements, meta, test_pid) do
    send(test_pid, {:enqueue, meta.name})
  end

  defmodule DefaultServing do
    use Agens.Serving
    @impl true
    def start(state), do: {:ok, state}
    @impl true
    def handle_message(_state, _msg, _schema), do: {:ok, "ok"}
    @impl true
    def handle_result({:ok, result}, _state, _msg), do: {:ok, result}
  end

  defmodule CustomOutputsServing do
    use Agens.Serving
    @impl true
    def start(state), do: {:ok, state}
    @impl true
    def handle_message(_state, _msg, _schema), do: {:ok, "ok"}
    @impl true
    def handle_result({:ok, result}, _state, _msg), do: {:ok, result}

    @impl true
    def outputs_schema(%Message{}) do
      {"outputs",
       %{
         "title" => "outputs",
         "type" => "object",
         "additionalProperties" => false,
         "required" => ["summary"],
         "properties" => %{
           "summary" => %{"type" => "string", "description" => "A brief summary"}
         }
       }}
    end
  end

  defmodule CustomToolsServing do
    use Agens.Serving
    @impl true
    def start(state), do: {:ok, state}
    @impl true
    def handle_message(_state, _msg, _schema), do: {:ok, "ok"}
    @impl true
    def handle_result({:ok, result}, _state, _msg), do: {:ok, result}

    @impl true
    def tools_schema(%Message{}) do
      {"tool_calls",
       %{
         "title" => "Custom Tool Calls",
         "type" => "array",
         "items" => %{"type" => "string"}
       }}
    end
  end

  defmodule CustomResponseServing do
    use Agens.Serving
    @impl true
    def start(state), do: {:ok, state}
    @impl true
    def handle_message(_state, _msg, _schema), do: {:ok, "ok"}
    @impl true
    def handle_result({:ok, result}, _state, _msg), do: {:ok, result}

    @impl true
    def response_schema(%Message{}) do
      %{
        "title" => "Custom",
        "type" => "object",
        "additionalProperties" => false,
        "properties" => %{
          "answer" => %{"type" => "string"}
        }
      }
    end
  end

  defmodule CustomResponseNoPropsServing do
    use Agens.Serving
    @impl true
    def start(state), do: {:ok, state}
    @impl true
    def handle_message(_state, _msg, _schema), do: {:ok, "ok"}
    @impl true
    def handle_result({:ok, result}, _state, _msg), do: {:ok, result}

    @impl true
    def response_schema(%Message{}) do
      %{"title" => "Minimal", "type" => "object"}
    end
  end

  defmodule CustomBuildSchemaServing do
    use Agens.Serving
    @impl true
    def start(state), do: {:ok, state}
    @impl true
    def handle_message(_state, _msg, _schema), do: {:ok, "ok"}
    @impl true
    def handle_result({:ok, result}, _state, _msg), do: {:ok, result}

    @impl true
    def build_schema(%Message{}) do
      %{"title" => "Fully Custom", "type" => "object", "properties" => %{}}
    end
  end

  defmodule QueueServing do
    use Agens.Serving, limit: 1

    @impl true
    def start(state), do: {:ok, state}

    @impl true
    def handle_message(_state, %Message{caller: caller, input: input}, _schema) do
      send(caller, {:started, input, self()})

      receive do
        :release -> :ok
      after
        5_000 -> :ok
      end

      {:ok, %Result{body: input}}
    end

    @impl true
    def handle_result({:ok, result}, _state, _msg), do: {:ok, result}
  end

  defp start_agens(_ctx) do
    {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})
    :ok
  end

  defp start_serving(_ctx) do
    config = %Serving.Config{
      name: :serving_test,
      serving: Test.Support.Serving
    }

    {:ok, pid} = Serving.start(config)

    [
      config: config,
      pid: pid
    ]
  end

  describe "stop" do
    setup [:start_agens, :start_serving]

    test "stop/1 terminates serving by name", %{config: config} do
      assert :ok == Serving.stop(config.name)
    end

    test "stop/1 returns error when serving not found" do
      assert {:error, :serving_not_found} == Serving.stop(:nonexistent_serving)
    end
  end

  describe "config" do
    setup [:start_agens, :start_serving]

    test "get config - by pid", %{pid: pid, config: config} do
      assert is_pid(pid)
      {:ok, serving} = Serving.get_config(pid)
      assert serving.name == config.name
    end

    test "get config - by name", %{config: config} do
      {:ok, serving} = Serving.get_config(config.name)
      assert serving.name == config.name
    end
  end

  describe "serving pid" do
    setup [:start_agens, :start_serving]

    test "get pid - by name", %{config: config} do
      Agens.serving_pid(config.name, {:error, :serving_not_found}, fn pid ->
        assert is_pid(pid)
      end)
    end

    test "get pid - not found" do
      assert {:error, :serving_not_found} ==
               Agens.serving_pid(:missing_serving, {:error, :serving_not_found}, & &1)
    end
  end

  describe "schema callbacks - defaults" do
    test "response_schema/1 returns base properties without sub-schemas" do
      schema = DefaultServing.response_schema(msg())
      props = schema["properties"]

      assert schema["type"] == "object"
      assert Map.has_key?(props, "body")
      assert Map.has_key?(props, "next")
      refute Map.has_key?(props, "outputs")
      refute Map.has_key?(props, "tool_calls")
    end

    test "outputs_schema/1 returns {key, schema} tuple with empty properties" do
      {key, schema} = DefaultServing.outputs_schema(msg())

      assert key == "outputs"
      assert schema["type"] == "object"
      assert schema["properties"] == %{}
      assert schema["required"] == []
    end

    test "tools_schema/1 returns {key, schema} tuple for MCP tool calls" do
      {key, schema} = DefaultServing.tools_schema(msg())

      assert key == "tool_calls"
      assert schema["type"] == "array"
      required = schema["items"]["required"]
      assert "id" in required
      assert "name" in required
      assert "arguments" in required
    end

    test "build_schema/1 composes all three sub-schemas" do
      schema = DefaultServing.build_schema(msg())
      props = schema["properties"]

      assert Map.has_key?(props, "body")
      assert Map.has_key?(props, "next")
      assert Map.has_key?(props, "outputs")
      assert Map.has_key?(props, "tool_calls")
    end

    test "build_schema/1 sets required from final properties keys" do
      schema = DefaultServing.build_schema(msg())
      required = schema["required"]

      assert is_list(required)
      assert Enum.sort(required) == Enum.sort(Map.keys(schema["properties"]))
    end
  end

  describe "schema callbacks - override outputs_schema" do
    test "build_schema uses custom outputs_schema" do
      schema = CustomOutputsServing.build_schema(msg())
      outputs = schema["properties"]["outputs"]

      assert outputs["required"] == ["summary"]
      assert Map.has_key?(outputs["properties"], "summary")
    end

    test "other defaults are preserved when only outputs_schema is overridden" do
      schema = CustomOutputsServing.build_schema(msg())
      props = schema["properties"]

      assert Map.has_key?(props, "body")
      assert Map.has_key?(props, "next")
      assert Map.has_key?(props, "tool_calls")
    end
  end

  describe "schema callbacks - override tools_schema" do
    test "build_schema uses custom tools_schema" do
      schema = CustomToolsServing.build_schema(msg())
      tool_calls = schema["properties"]["tool_calls"]

      assert tool_calls["title"] == "Custom Tool Calls"
      assert tool_calls["items"] == %{"type" => "string"}
    end

    test "other defaults are preserved when only tools_schema is overridden" do
      schema = CustomToolsServing.build_schema(msg())
      props = schema["properties"]

      assert Map.has_key?(props, "body")
      assert Map.has_key?(props, "next")
      assert Map.has_key?(props, "outputs")
    end
  end

  describe "schema callbacks - override response_schema" do
    test "build_schema merges sub-schemas into custom response_schema properties" do
      schema = CustomResponseServing.build_schema(msg())
      props = schema["properties"]

      assert Map.has_key?(props, "answer")
      assert Map.has_key?(props, "outputs")
      assert Map.has_key?(props, "tool_calls")
    end

    test "build_schema handles response_schema without properties key" do
      schema = CustomResponseNoPropsServing.build_schema(msg())
      props = schema["properties"]

      assert Map.has_key?(props, "outputs")
      assert Map.has_key?(props, "tool_calls")
    end
  end

  describe "schema callbacks - override build_schema" do
    test "custom build_schema is used as-is without calling sub-schemas" do
      schema = CustomBuildSchemaServing.build_schema(msg())

      assert schema["title"] == "Fully Custom"
      assert schema["properties"] == %{}
    end
  end

  describe "schema callbacks - combined overrides" do
    test "overriding both outputs_schema and tools_schema composes correctly" do
      schema = CustomOutputsServing.build_schema(msg())
      props = schema["properties"]

      # outputs is customized
      assert props["outputs"]["required"] == ["summary"]
      # tools uses default (array of objects with id/name/arguments)
      assert props["tool_calls"]["type"] == "array"
    end
  end

  describe "build_prompt/3 - default" do
    test "renders binary fields with heading and detail in system/user strings" do
      message = %Message{
        input: "hello world",
        node_objective: "answer the question",
        job_description: "the full job"
      }

      {system, user} = DefaultServing.build_prompt(message, Prefixes.default(), nil)

      assert system =~ "## Node Objective"
      assert system =~ "The objective of this node is to:"
      assert system =~ "answer the question"
      assert system =~ "## Job Description"
      assert system =~ "the full job"

      assert user =~ "## Input"
      assert user =~ "The following is the original input from the user:"
      assert user =~ "hello world"
    end

    test "includes context in the system prompt when a binary context is provided" do
      {system, _user} =
        DefaultServing.build_prompt(%Message{input: "x"}, Prefixes.default(), "extra context")

      assert system =~ "## Context"
      assert system =~ "extra context"
    end

    test "omits context section when context is nil" do
      {system, _user} =
        DefaultServing.build_prompt(%Message{input: "x"}, Prefixes.default(), nil)

      refute system =~ "## Context"
    end

    test "defaults context to nil when omitted" do
      {system, _user} = DefaultServing.build_prompt(%Message{input: "x"}, Prefixes.default())

      refute system =~ "## Context"
    end

    test "JSON-encodes map values (tool_results)" do
      message = %Message{
        input: "x",
        tool_results: %{"call_1" => "result_a"}
      }

      {_system, user} = DefaultServing.build_prompt(message, Prefixes.default(), nil)

      assert user =~ "## Tool Results"
      assert user =~ Jason.encode!(%{"call_1" => "result_a"})
    end

    test "JSON-encodes list values (tool_defs and tool_calls)" do
      tool_defs = [%{"name" => "search", "description" => "search the web"}]
      tool_calls = [%{"id" => "tc_1", "name" => "search", "arguments" => []}]

      message = %Message{
        input: "x",
        tool_defs: tool_defs,
        tool_calls: tool_calls
      }

      {system, user} = DefaultServing.build_prompt(message, Prefixes.default(), nil)

      assert system =~ "## Tool Definitions"
      assert system =~ Jason.encode!(tool_defs)

      assert user =~ "## Tool Calls"
      assert user =~ Jason.encode!(tool_calls)
    end

    test "omits sections whose values are nil or empty" do
      {system, user} =
        DefaultServing.build_prompt(%Message{input: "only input"}, Prefixes.default(), nil)

      refute system =~ "## Node Objective"
      refute system =~ "## Job Description"
      refute user =~ "## Previous Result"
      refute user =~ "## Tool Calls"
    end
  end

  describe "queue behavior" do
    setup [:start_agens]

    defp queue_run(serving_name, input) do
      caller = self()

      spawn_link(fn ->
        msg = %Message{caller: caller, input: input, serving_name: serving_name}
        send(caller, {:done, input, Serving.run(msg)})
      end)
    end

    test "queues runs beyond the limit and drains them FIFO as :result fires" do
      {:ok, pid} =
        Serving.start(%Serving.Config{name: :queue_serving, serving: QueueServing})

      queue_run(:queue_serving, "a")
      queue_run(:queue_serving, "b")
      queue_run(:queue_serving, "c")

      assert_receive {:started, "a", task_a}, 1_000
      refute_receive {:started, "b", _}, 100

      state = :sys.get_state(pid)
      assert state.count == 1
      assert state.limit == 1
      assert :queue.len(state.queue) == 2

      send(task_a, :release)
      assert_receive {:done, "a", {:ok, %Result{body: "a"}}}, 1_000

      assert_receive {:started, "b", task_b}, 1_000

      state = :sys.get_state(pid)
      assert state.count == 1
      assert :queue.len(state.queue) == 1

      send(task_b, :release)
      assert_receive {:done, "b", {:ok, %Result{body: "b"}}}, 1_000

      assert_receive {:started, "c", task_c}, 1_000
      send(task_c, :release)
      assert_receive {:done, "c", {:ok, %Result{body: "c"}}}, 1_000

      # Allow the final :result message to be processed
      :sys.get_state(pid)
      state = :sys.get_state(pid)
      assert state.count == 0
      assert :queue.is_empty(state.queue)
    end

    test "emits [:agens, :serving, :enqueue] telemetry on each run" do
      handler_id = "enqueue-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:agens, :serving, :enqueue],
        &__MODULE__.forward_telemetry/4,
        self()
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, _pid} =
        Serving.start(%Serving.Config{name: :enqueue_telemetry_serving, serving: QueueServing})

      queue_run(:enqueue_telemetry_serving, "x")

      assert_receive {:enqueue, :enqueue_telemetry_serving}, 1_000
      assert_receive {:started, "x", task}, 1_000

      send(task, :release)
      assert_receive {:done, "x", {:ok, _}}, 1_000
    end
  end
end
