defmodule AgensTest do
  use Test.Support.AgentCase, async: true
  doctest Agens

  alias Agens.Job

  describe "job" do
    test "start agents", %{agents: agents} do
      assert length(agents) == 3
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

    @tag timeout: :infinity
    test "message sequence without job" do
      input = "D"

      %{results: [%{text: text0}]} = Agens.message(:first_agent, input)
      input1 = post_process(text0)
      assert input1 == "C"
      %{results: [%{text: text1}]} = Agens.message(:second_agent, input1)
      input2 = post_process(text1)
      assert input2 == "E"
      %{results: [%{text: text2}]} = Agens.message(:verifier_agent, input2)
      verify1 = post_process(text2)
      assert verify1 == "FALSE"

      %{results: [%{text: text3}]} = Agens.message(:first_agent, input2)
      input4 = post_process(text3)
      assert input4 == "D"
      %{results: [%{text: text4}]} = Agens.message(:second_agent, input4)
      input5 = post_process(text4)
      assert input5 == "F"
      %{results: [%{text: text5}]} = Agens.message(:verifier_agent, input5)
      verify2 = post_process(text5)
      assert verify2 == "FALSE"

      %{results: [%{text: text6}]} = Agens.message(:first_agent, input5)
      input7 = post_process(text6)
      assert input7 == "E"
      %{results: [%{text: text7}]} = Agens.message(:second_agent, input7)
      input8 = post_process(text7)
      assert input8 == "G"
      %{results: [%{text: text8}]} = Agens.message(:verifier_agent, input8)
      verify3 = post_process(text8)
      assert verify3 == "TRUE"
    end

    test "invalid message returns error" do
      msg = "Here is some invalid input"

      %{results: [%{text: text}]} = Agens.message(:second_agent, msg)

      assert text == "ERROR"
    end

    test "message non-existent agent" do
      result = Agens.message(:missing_agent, "J")
      assert result == {:error, :agent_not_running}
    end

    test "stop non-existent agent" do
      result = Agens.stop_agent(:missing_agent)
      assert result == {:error, :agent_not_found}
    end

    test "start job" do
      job = %Job.Config{
        name: :first_job,
        objective: "to create a sequence of steps",
        steps: [
          %Job.Step{
            agent: :first_agent,
            prompt: "",
            conditions: ""
          },
          %Job.Step{
            agent: :second_agent,
            prompt: "",
            conditions: ""
          },
          %Job.Step{
            agent: :verifier_agent,
            prompt: "",
            conditions: ""
          }
        ]
      }

      {:ok, pid} = Agens.start_job(job)
      assert is_pid(pid)
      assert job == Job.get_config(pid)
      assert job == Job.get_config(:first_job)
      assert {:error, :job_not_found} == Job.get_config(:missing_job)
    end
  end
end
