defmodule Agens.AgentTest do
  use Test.Support.AgentCase, async: true
  doctest Agens.Agent

  alias Agens.Agent

  describe "agents" do
    test "start agents", %{text_generation: text_generation} do
      agents =
        [
          %Agent.Config{
            name: :test_start_agent,
            serving: text_generation
          }
        ]
        |> Agent.start()

      assert length(agents) == 1
      [{:ok, pid}] = agents
      assert is_pid(pid)
    end

    @tag :skip
    test "stop agent", %{text_generation: text_generation} do
      agents =
        [
          %Agent.Config{
            name: :test_stop_agent,
            serving: text_generation
          }
        ]
        |> Agent.start()

      assert length(agents) == 1
      [{:ok, pid}] = agents
      assert is_pid(pid)

      result = Agent.stop(:test_stop_agent)
      assert result

      result = Agent.message(:test_stop_agent, "test")
      assert result == {:error, :agent_not_running}
    end

    test "stop non-existent agent" do
      result = Agent.stop(:missing_agent)
      assert result == {:error, :agent_not_found}
    end
  end

  describe "messages" do
    @tag timeout: :infinity
    test "message sequence without job", %{text_generation: text_generation} do
      text_generation
      |> get_agent_configs()
      |> Agent.start()

      input = "D"

      # 0
      {:ok, text0} = Agent.message(:first_agent, input)
      input1 = post_process(text0)
      assert input1 == "C"
      {:ok, text1} = Agent.message(:second_agent, input1)
      input2 = post_process(text1)
      assert input2 == "E"
      {:ok, text2} = Agent.message(:verifier_agent, input2)
      verify1 = post_process(text2)
      assert verify1 == "FALSE"

      # 1
      {:ok, text3} = Agent.message(:first_agent, input2)
      input4 = post_process(text3)
      assert input4 == "D"
      {:ok, text4} = Agent.message(:second_agent, input4)
      input5 = post_process(text4)
      assert input5 == "F"
      {:ok, text5} = Agent.message(:verifier_agent, input5)
      verify2 = post_process(text5)
      assert verify2 == "FALSE"

      # 2
      {:ok, text6} = Agent.message(:first_agent, input5)
      input7 = post_process(text6)
      assert input7 == "E"
      {:ok, text7} = Agent.message(:second_agent, input7)
      input8 = post_process(text7)
      assert input8 == "G"
      {:ok, text8} = Agent.message(:verifier_agent, input8)
      verify3 = post_process(text8)
      assert verify3 == "TRUE"
    end

    @tag :skip
    test "invalid message returns error", %{text_generation: text_generation} do
      [
        %Agent.Config{
          name: :test_start_agent,
          serving: text_generation
        }
      ]
      |> Agent.start()

      msg = "Here is some invalid input"

      {:ok, text} = Agent.message(:second_agent, msg)

      assert text == "ERROR"
    end

    test "message non-existent agent" do
      result = Agent.message(:missing_agent, "J")
      assert result == {:error, :agent_not_running}
    end
  end
end
