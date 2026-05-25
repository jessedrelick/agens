defmodule Test.Support.Tools do
  def tool_def() do
    %{}
    |> Jason.encode!()
  end

  def tool_call(_call_id) do
    %{
      "id" => "tool_call_id",
      "name" => "test_tool_name",
      "arguments" => [
        %{
          "key" => "tool_arg_1_key",
          "value" => "tool_arg_1_value"
        }
      ]
    }
  end

  def tool_exec(tool_call), do: {tool_call["id"], "tool result for: #{tool_call["id"]}"}
end
