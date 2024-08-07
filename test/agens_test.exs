defmodule AgensTest do
  use Test.Support.AgentCase, async: true
  doctest Agens

  describe "agents" do
    test "start agents", %{agents: agents} do
      assert length(agents) == 4
      [{:ok, pid} | _] = agents
      assert is_pid(pid)
    end

    @tag :skip
    test "stop agent" do
      result = Agens.stop_agent(:first_agent)
      assert result

      result = Agens.message(:first_agent, "B")
      assert result == {:error, :agent_not_running}
    end

    test "stop non-existent agent" do
      result = Agens.stop_agent(:missing_agent)
      assert result == {:error, :agent_not_found}
    end
  end

  describe "messages" do
    @tag timeout: :infinity
    test "message sequence without job" do
      input = "D"

      # 0
      {:ok, text0} = Agens.message(:first_agent, input)
      input1 = post_process(text0)
      assert input1 == "C"
      {:ok, text1} = Agens.message(:second_agent, input1)
      input2 = post_process(text1)
      assert input2 == "E"
      {:ok, text2} = Agens.message(:verifier_agent, input2)
      verify1 = post_process(text2)
      assert verify1 == "FALSE"

      # 1
      {:ok, text3} = Agens.message(:first_agent, input2)
      input4 = post_process(text3)
      assert input4 == "D"
      {:ok, text4} = Agens.message(:second_agent, input4)
      input5 = post_process(text4)
      assert input5 == "F"
      {:ok, text5} = Agens.message(:verifier_agent, input5)
      verify2 = post_process(text5)
      assert verify2 == "FALSE"

      # 2
      {:ok, text6} = Agens.message(:first_agent, input5)
      input7 = post_process(text6)
      assert input7 == "E"
      {:ok, text7} = Agens.message(:second_agent, input7)
      input8 = post_process(text7)
      assert input8 == "G"
      {:ok, text8} = Agens.message(:verifier_agent, input8)
      verify3 = post_process(text8)
      assert verify3 == "TRUE"
    end

    test "invalid message returns error" do
      msg = "Here is some invalid input"

      {:ok, text} = Agens.message(:second_agent, msg)

      assert text == "ERROR"
    end

    test "message non-existent agent" do
      result = Agens.message(:missing_agent, "J")
      assert result == {:error, :agent_not_running}
    end
  end
end
