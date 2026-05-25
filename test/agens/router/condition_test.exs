defmodule Agens.Router.ConditionTest do
  use ExUnit.Case, async: true

  alias Agens.Router.{Condition, Output}

  defp output(key, type, value), do: %Output{key: key, type: type, value: value}

  describe "check/2" do
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
end
