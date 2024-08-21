defmodule Test.ToolTest do
  use Test.Support.AgentCase, async: true

  defmodule TestTool do
    @behaviour Agens.Tool
    def pre(input), do: "pre: #{input}"
    def instructions(), do: "test tool instructions"
    def to_args(_input), do: [t: "e", s: "t"]
    def execute(args), do: Enum.into(args, %{})
    def post(result), do: Enum.map(result, fn {k, v} -> "#{k}: #{v}" end) |> Enum.join(", ")
  end

  describe "tool" do
    test "all" do
      input = "test"
      result = "test"

      assert TestTool.pre(input) == "pre: #{input}"
      assert TestTool.instructions() == "test tool instructions"

      args = TestTool.to_args(result)
      assert args == [t: "e", s: "t"]

      result = TestTool.execute(args)
      assert result == %{t: "e", s: "t"}

      post = TestTool.post(result)
      assert post =~ "t: e"
      assert post =~ "s: t"
    end
  end
end
