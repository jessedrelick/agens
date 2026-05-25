defmodule Agens.Schema do
  @moduledoc """
  JSON Schema fragments used to constrain structured LM responses.

  Servings using structured outputs combine these fragments via
  `c:Agens.Serving.build_schema/1` into a single JSON Schema describing the
  expected response shape: a `body` string, a `next` list of routing instructions,
  an `outputs` map, and a `tool_calls` array modeled after MCP tool calls.

  The default `Agens.Serving` implementation wires each fragment in through
  the `c:Agens.Serving.response_schema/1`, `c:Agens.Serving.outputs_schema/1` and
  `c:Agens.Serving.tools_schema/1` callbacks - override those callbacks in a Serving
  to supply a different schema (for example, to declare a Router-specific `outputs` schema).
  """

  @doc """
  Returns the base response schema (`body` + `next`).

  Used by `c:Agens.Serving.response_schema/1` as the foundation that `outputs` and
  `tool_calls` properties are added onto.
  """
  @spec response() :: map()
  def response() do
    %{
      "title" => "Agens.StructuredOutput",
      "description" => "Structured Output response for an Agens Message",
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "body" => %{
          "title" => "body",
          "description" => "Main body of response",
          "type" => "string"
        },
        "next" => %{
          "title" => "next",
          "description" => "List of Agens route instructions",
          "type" => "array",
          "items" => %{
            "type" => "object",
            "required" => ["type", "value"],
            "properties" => %{
              "type" => %{
                "title" => "route instruction type",
                "description" =>
                  "Type of route instruction. Use `route` for explicit routing to another Node. Use `yield` for yielding to another Node for aggregation. Use `sub` for starting a new sub job. Use `end` for ending the current job. Use `retry` for retrying the current operation. IMPORTANT: Only return an empty list for `next` unless explicitly told to route dynamically and the Agens Routing Resource is included in the current prompt. The LLM should not hallucinate or force `next` values, and should only return one or more items if instructed to do so. `next` is a dynamic, LLM-based override for standard, explicit routing.",
                "type" => "string",
                "enum" => ["route", "yield", "sub", "end", "retry"]
              },
              "value" => %{
                "title" => "route instruction value",
                "description" =>
                  "Value of route instruction. This is either a Node ID (if type is `route` or `yield`) or a Job ID (if type is `sub`).",
                "type" => "string"
              }
            },
            "additionalProperties" => false
          }
        }
      }
    }
  end

  @doc """
  Returns the default `outputs` schema fragment.

  Servings declaring structured outputs typically override `c:Agens.Serving.outputs_schema/1`
  to return a Router-specific schema derived from `Agens.Router.Output.to_json_schema/1`.
  """
  @spec outputs() :: map()
  def outputs() do
    %{
      "title" => "outputs",
      "description" => "An object with arbitrary keys and values, e.g. { key: value }",
      "type" => "object",
      "required" => [],
      "additionalProperties" => false,
      "properties" => %{}
    }
  end

  @doc """
  Returns the `tool_calls` schema fragment modeled after the MCP Tool Calls shape.
  """
  @spec tools() :: map()
  def tools() do
    %{
      "title" => "MCP Tool Calls list",
      "description" =>
        "Schema describing tool calls emitted in structured LLM outputs, modeled after MCP Tool Calls.",
      "type" => "array",
      "additionalProperties" => false,
      "items" => %{
        "title" => "MCP Tool Call schema",
        "type" => "object",
        "required" => ["id", "name", "arguments", "server_name", "type"],
        "additionalProperties" => false,
        "properties" => %{
          "id" => %{
            "type" => "string",
            "description" => "Unique identifier for the tool call instance."
          },
          "name" => %{
            "type" => "string",
            "description" => "The name of the tool being invoked (must match a defined tool)."
          },
          "arguments" => %{
            "type" => "array",
            "description" =>
              "List of key-value pairs representing tool arguments. Each key and value are strings for strict validation.",
            "items" => %{
              "type" => "object",
              "additionalProperties" => false,
              "required" => ["key", "value"],
              "properties" => %{
                "key" => %{"type" => "string"},
                "value" => %{"type" => "string"}
              }
            }
          },
          "server_name" => %{
            "type" => "string",
            "description" => "Optional MCP server identifier or namespace (if applicable)."
          },
          "type" => %{
            "type" => "string",
            "enum" => ["mcp_tool_use", "tool_call"],
            "description" => "Type discriminator for compatibility with MCP messages."
          }
        }
      }
    }
  end
end
