defmodule Agens.PrefixesTest do
  use ExUnit.Case, async: false

  alias Agens.Prefixes

  @tool_defs """
  You have access to the following MCP tools. If you need to call one or more tools to complete \
  the task, populate the `tool_calls` field in your structured response. If tool results have \
  already been provided, use them to generate your response in `body` and `outputs` instead of \
  making additional tool calls. The available tools are:
  """

  describe "prefixes" do
    test "default" do
      assert %Prefixes{
               context: {"Context", "The following is critical context relevant to this task"},
               objective: {"Node Objective", "The objective of this node is to"},
               description:
                 {"Job Description", "This is part of a multi-node job to achieve the following"},
               input: {"Input", "The following is the original input from the user"},
               previous_result:
                 {"Previous Result",
                  "The following is the result from the previous node in this job"},
               schema:
                 {"Schema",
                  "It is critical to only return a JSON object matching the exact specification below"},
               retry:
                 {"Retry",
                  "The response did not pass validation. Please try again and fix the following validation errors"},
               tool_defs: {"Tool Definitions", @tool_defs},
               tool_calls: {"Tool Calls", "The following MCP tool calls were made by this node"},
               tool_results:
                 {"Tool Results",
                  "The following are the results of MCP tool calls for this node. Use these results to formulate your response in `body` and `outputs`"},
               resources:
                 {"Resources", "The following resources are provided as context for this node"}
             } = Prefixes.default()
    end
  end
end
