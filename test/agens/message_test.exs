defmodule Agens.MessageTest do
  use Test.Support.AgentCase, async: false

  alias Agens.Message

  defp start_agens(_ctx) do
    {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})
    :ok
  end

  defp start_serving(_ctx) do
    %Agens.Serving.Config{
      name: :text_generation,
      serving: Test.Support.Serving.Stub
    }
    |> Agens.Serving.start()

    :ok
  end

  describe "no agent or serving" do
    test "returns error" do
      assert {:error, :no_agent_or_serving_name} == Message.send(%Message{})
    end
  end

  describe "no agent" do
    setup [:start_agens, :start_serving]

    test "works with explicit serving" do
      serving_name = :text_generation

      assert %Message{
               input: "test",
               serving_name: serving_name,
               result: "sent 'test' to: ",
               prompt:
                 "<s>[INST]## Input\nThe following is the actual input from the user, system or another agent: test\n[/INST]"
             } == Message.send(%Message{serving_name: serving_name, input: "test"})
    end
  end
end
