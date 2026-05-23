defmodule Agens.PromptTest do
  use ExUnit.Case, async: true

  alias Agens.{Message, Prefixes, Prompt}

  test "build/3 includes context in system pairs when a binary context is provided" do
    message = %Message{input: "test input"}
    prefixes = Prefixes.default()

    {system, _user} = Prompt.build(message, prefixes, "some context")

    values = Enum.map(system, fn {_prefix, value} -> value end)
    assert "some context" in values
  end

  test "build/3 excludes context from system pairs when context is nil" do
    message = %Message{input: "test input", node_objective: "obj", job_description: "desc"}
    prefixes = Prefixes.default()

    {system, _user} = Prompt.build(message, prefixes, nil)

    keys = Enum.map(system, fn {_prefix, value} -> value end)
    refute "nil" in keys
    refute nil in keys
    assert "obj" in keys
    assert "desc" in keys
  end
end
