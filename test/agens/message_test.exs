defmodule Agens.MessageTest do
  use Test.Support.AgentCase, async: false

  alias Agens.Message

  def wrap_prompt(prompt), do: "<s>[INST]#{prompt}[/INST]"

  defp start_agens(_ctx) do
    {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})
    :ok
  end

  defp start_serving(_ctx) do
    %Agens.Serving.Config{
      name: :text_generation,
      serving: Test.Support.Serving.Stub,
      finalize: &wrap_prompt/1
    }
    |> Agens.Serving.start()

    :ok
  end

  describe "errors" do
    test "input required" do
      assert {:error, :input_required} == Message.send(%Message{serving_name: :text_generation})
    end

    test "no agent or serving" do
      assert {:error, :no_agent_or_serving_name} == Message.send(%Message{input: "test"})
    end
  end

  describe "no agent" do
    setup [:start_agens, :start_serving]

    test "works with explicit serving" do
      serving_name = :text_generation

      wrapped =
        wrap_prompt(
          "## Input\nThe following is the actual input from the user, system or another agent: test\n"
        )

      assert %Message{
               input: "test",
               serving_name: serving_name,
               result: "sent 'test' to: ",
               prompt: wrapped
             } == Message.send(%Message{serving_name: serving_name, input: "test"})
    end
  end
end
