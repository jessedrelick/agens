defmodule Agens.SchemaTest do
  use ExUnit.Case, async: true

  alias Agens.Schema

  describe "response/0" do
    test "returns the base response schema with body and next properties" do
      schema = Schema.response()

      assert %{
               "title" => "Agens.StructuredOutput",
               "type" => "object",
               "additionalProperties" => false,
               "properties" => %{
                 "body" => %{"type" => "string"},
                 "next" => %{"type" => "array", "items" => items}
               }
             } = schema

      assert %{
               "type" => "object",
               "required" => ["type", "value"],
               "additionalProperties" => false,
               "properties" => %{
                 "type" => %{"type" => "string", "enum" => enum},
                 "value" => %{"type" => "string"}
               }
             } = items

      assert Enum.sort(enum) == Enum.sort(["route", "yield", "sub", "end", "retry"])
    end

    test "is JSON-encodable" do
      assert {:ok, _json} = Jason.encode(Schema.response())
    end
  end

  describe "outputs/0" do
    test "returns an empty outputs object schema" do
      assert %{
               "title" => "outputs",
               "type" => "object",
               "required" => [],
               "additionalProperties" => false,
               "properties" => %{}
             } = Schema.outputs()
    end

    test "is JSON-encodable" do
      assert {:ok, _json} = Jason.encode(Schema.outputs())
    end
  end

  describe "tools/0" do
    test "returns the MCP-style tool_calls array schema" do
      schema = Schema.tools()

      assert %{
               "title" => "MCP Tool Calls list",
               "type" => "array",
               "additionalProperties" => false,
               "items" => items
             } = schema

      assert %{
               "type" => "object",
               "required" => ["id", "name", "arguments", "server_name", "type"],
               "additionalProperties" => false,
               "properties" => properties
             } = items

      assert %{
               "id" => %{"type" => "string"},
               "name" => %{"type" => "string"},
               "server_name" => %{"type" => "string"},
               "type" => %{"type" => "string", "enum" => ["mcp_tool_use", "tool_call"]},
               "arguments" => %{"type" => "array", "items" => arg_items}
             } = properties

      assert %{
               "type" => "object",
               "required" => ["key", "value"],
               "additionalProperties" => false,
               "properties" => %{
                 "key" => %{"type" => "string"},
                 "value" => %{"type" => "string"}
               }
             } = arg_items
    end

    test "is JSON-encodable" do
      assert {:ok, _json} = Jason.encode(Schema.tools())
    end
  end
end
