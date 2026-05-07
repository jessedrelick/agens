defmodule Agens.RouterTest do
  use ExUnit.Case, async: true

  alias Agens.{Message, Router}
  alias Agens.Router.{Condition, Output}

  defmodule TestRouter do
    use Agens.Router

    @impl Agens.Router
    def outputs(%Message{job_id: "scored_job"}) do
      [
        %Output{key: "score", type: "int"},
        %Output{key: "pass", type: "bool"}
      ]
    end

    def outputs(%Message{}), do: []

    @impl Agens.Router
    def resolve(%Message{}, outputs) do
      case Enum.find(outputs, &(&1.key == "pass")) do
        %Output{value: true} -> [{:route, "next_node", 1}]
        _ -> [:retry]
      end
    end
  end

  # ===========================================================================
  # parse_next/1
  # ===========================================================================

  describe "parse_next/1" do
    test "route" do
      assert Router.parse_next([%{"type" => "route", "value" => "node_a"}]) ==
               [{:route, "node_a", 1}]
    end

    test "yield" do
      assert Router.parse_next([%{"type" => "yield", "value" => "node_b"}]) ==
               [{:yield, "node_b"}]
    end

    test "job" do
      assert Router.parse_next([%{"type" => "job", "value" => "other_job"}]) ==
               [{:job, "other_job"}]
    end

    test "end" do
      assert Router.parse_next([%{"type" => "end"}]) == [:end]
    end

    test "retry" do
      assert Router.parse_next([%{"type" => "retry"}]) == [:retry]
    end

    test "unknown type is filtered out" do
      assert Router.parse_next([%{"type" => "unknown", "value" => "x"}]) == []
    end

    test "mixed valid and invalid" do
      input = [
        %{"type" => "route", "value" => "node_a"},
        %{"type" => "unknown"},
        %{"type" => "end"}
      ]

      assert Router.parse_next(input) == [{:route, "node_a", 1}, :end]
    end

    test "empty list" do
      assert Router.parse_next([]) == []
    end
  end

  # ===========================================================================
  # route/1 and route/2
  # ===========================================================================

  describe "route/1" do
    test "calls resolve when all output keys present" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      assert TestRouter.route(message) == [{:route, "next_node", 1}]
    end

    test "returns retry when output keys missing" do
      message = %Message{input: "test", job_id: "scored_job", outputs: %{"score" => 9}}

      assert TestRouter.route(message) == [:retry]
    end

    test "returns retry when outputs is nil" do
      message = %Message{input: "test", job_id: "scored_job", outputs: nil}

      assert TestRouter.route(message) == [:retry]
    end

    test "calls resolve with empty outputs when no outputs defined" do
      message = %Message{input: "test", job_id: "no_outputs_job", outputs: %{}}

      assert TestRouter.route(message) == [:retry]
    end
  end

  describe "route/2" do
    test "uses dynamic_next when non-empty and valid" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      dynamic = [%{"type" => "route", "value" => "override_node"}]

      assert TestRouter.route(message, dynamic) == [{:route, "override_node", 1}]
    end

    test "falls through to route/1 when dynamic_next is empty list" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      assert TestRouter.route(message, []) == [{:route, "next_node", 1}]
    end

    test "falls through to route/1 when dynamic_next is nil" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      assert TestRouter.route(message, nil) == [{:route, "next_node", 1}]
    end

    test "falls through to route/1 when all dynamic_next entries are invalid" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      dynamic = [%{"type" => "unknown"}, %{"type" => "also_unknown"}]

      assert TestRouter.route(message, dynamic) == [{:route, "next_node", 1}]
    end

    test "dynamic_next overrides even when static routing would succeed" do
      message = %Message{
        input: "test",
        job_id: "scored_job",
        outputs: %{"score" => 9, "pass" => true}
      }

      dynamic = [%{"type" => "end"}]

      assert TestRouter.route(message, dynamic) == [:end]
    end
  end

  # ===========================================================================
  # Condition.check/2
  # ===========================================================================

  describe "Condition.check/2" do
    defp output(key, type, value), do: %Output{key: key, type: type, value: value}

    test "eq matches equal values" do
      condition = %Condition{key: "status", op: "eq", value: "done"}
      outputs = [output("status", "string", "done")]
      assert Condition.check(condition, outputs)
    end

    test "eq fails on unequal values" do
      condition = %Condition{key: "status", op: "eq", value: "done"}
      outputs = [output("status", "string", "pending")]
      refute Condition.check(condition, outputs)
    end

    test "neq" do
      condition = %Condition{key: "status", op: "neq", value: "done"}
      outputs = [output("status", "string", "pending")]
      assert Condition.check(condition, outputs)
    end

    test "gt" do
      condition = %Condition{key: "score", op: "gt", value: "5"}
      outputs = [output("score", "int", 8)]
      assert Condition.check(condition, outputs)
    end

    test "lt" do
      condition = %Condition{key: "score", op: "lt", value: "5"}
      outputs = [output("score", "int", 3)]
      assert Condition.check(condition, outputs)
    end

    test "gte matches equal" do
      condition = %Condition{key: "score", op: "gte", value: "7"}
      outputs = [output("score", "int", 7)]
      assert Condition.check(condition, outputs)
    end

    test "lte matches equal" do
      condition = %Condition{key: "score", op: "lte", value: "7"}
      outputs = [output("score", "int", 7)]
      assert Condition.check(condition, outputs)
    end

    test "coerces bool string to boolean" do
      condition = %Condition{key: "pass", op: "eq", value: "true"}
      outputs = [output("pass", "bool", true)]
      assert Condition.check(condition, outputs)
    end

    test "coerces int string to integer" do
      condition = %Condition{key: "score", op: "eq", value: "9"}
      outputs = [output("score", "int", 9)]
      assert Condition.check(condition, outputs)
    end

    test "returns false when output key not found" do
      condition = %Condition{key: "missing", op: "eq", value: "x"}
      outputs = [output("other", "string", "x")]
      refute Condition.check(condition, outputs)
    end

    test "returns false when output value is nil" do
      condition = %Condition{key: "score", op: "eq", value: "5"}
      outputs = [output("score", "int", nil)]
      refute Condition.check(condition, outputs)
    end

    test "returns false against empty outputs" do
      condition = %Condition{key: "score", op: "gt", value: "0"}
      refute Condition.check(condition, [])
    end

    test "coerces bool false string to false" do
      condition = %Condition{key: "pass", op: "eq", value: "false"}
      outputs = [output("pass", "bool", false)]
      assert Condition.check(condition, outputs)
    end

    test "condition with nil value coerces to nil" do
      condition = %Condition{key: "status", op: "neq", value: nil}
      outputs = [output("status", "string", "done")]
      assert Condition.check(condition, outputs)
    end
  end

  # ===========================================================================
  # Output.to_json_schema/1
  # ===========================================================================

  describe "Output.to_json_schema/1" do
    test "empty list returns empty map" do
      assert Output.to_json_schema([]) == %{}
    end

    test "bool type" do
      schema = Output.to_json_schema([%Output{key: "pass", type: "bool", description: "Pass?"}])
      assert schema["pass"]["type"] == "boolean"
    end

    test "int type" do
      schema = Output.to_json_schema([%Output{key: "score", type: "int", description: "Score"}])
      assert schema["score"]["type"] == "integer"
    end

    test "int type with meta min/max" do
      schema =
        Output.to_json_schema([
          %Output{key: "score", type: "int", description: "Score", meta: %{min: 1, max: 10}}
        ])

      assert schema["score"]["minimum"] == 1
      assert schema["score"]["maximum"] == 10
    end

    test "string type" do
      schema =
        Output.to_json_schema([%Output{key: "label", type: "string", description: "Label"}])

      assert schema["label"]["type"] == "string"
    end

    test "enum type includes enum values" do
      schema =
        Output.to_json_schema([
          %Output{key: "tier", type: "enum", description: "Tier", values: ["low", "mid", "high"]}
        ])

      assert schema["tier"]["type"] == "string"
      assert schema["tier"]["enum"] == ["low", "mid", "high"]
    end

    test "multiple outputs keyed by output key" do
      schema =
        Output.to_json_schema([
          %Output{key: "pass", type: "bool", description: "Pass?"},
          %Output{key: "score", type: "int", description: "Score"}
        ])

      assert Map.has_key?(schema, "pass")
      assert Map.has_key?(schema, "score")
    end
  end
end
