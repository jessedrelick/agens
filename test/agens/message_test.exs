defmodule Agens.MessageTest do
  use ExUnit.Case, async: false

  alias Agens.{Message, Serving}

  defp start_agens(_ctx) do
    {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})
    :ok
  end

  defp start_serving(_ctx) do
    %Serving.Config{
      name: :test_serving,
      serving: Test.Support.Serving
    }
    |> Serving.start()

    :ok
  end

  describe "errors" do
    test "no input" do
      assert {:error, :input_required} == Message.send(%Message{input: nil})
      assert {:error, :input_required} == Message.send(%Message{input: ""})
    end

    test "no agent or serving" do
      assert {:error, :no_agent_or_serving_name} == Message.send(%Message{input: "test"})
    end

    test "invalid serving" do
      assert {:error, :serving_not_found} ==
               Message.send(%Message{input: "test", serving_name: :invalid_serving})
    end
  end

  describe "send" do
    setup [:start_agens, :start_serving]

    test "returns result message and emits prompt" do
      serving_name = :test_serving
      node_objective = "some node objective"
      input = "test input"
      pid = self()

      {:ok, %Serving.Config{prefixes: %Agens.Prefixes{} = prefixes}} =
        Serving.get_config(:test_serving)

      %{
        input: {input_heading, input_prefix},
        objective: {objective_heading, objective_prefix}
      } = prefixes

      expected_system =
        "## #{objective_heading}\n#{objective_prefix}:\n\n#{node_objective}\n"

      expected_user =
        "## #{input_heading}\n#{input_prefix}:\n\n#{input}\n"

      assert %Message{
               input: input,
               serving_name: serving_name,
               result: "sent '#{input}' to: ",
               caller: pid,
               tool_calls: %{},
               outputs: %{},
               node_objective: node_objective
             } ==
               Message.send(%Message{
                 caller: pid,
                 serving_name: serving_name,
                 input: input,
                 node_objective: node_objective
               })

      assert_receive {:prompt, {^expected_system, ^expected_user}}
    end
  end
end
