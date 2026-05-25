defmodule Agens.Router.OutputTest do
  use ExUnit.Case, async: true

  alias Agens.Router.Output

  describe "to_json_schema/1" do
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
          %Output{
            key: "tier",
            type: "enum",
            description: "Tier",
            meta: %{choices: ["low", "mid", "high"]}
          }
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
