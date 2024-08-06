defmodule Agens.JobTest do
  use Test.Support.AgentCase, async: true
  doctest Agens

  alias Agens.Job

  setup_all do
    job = %Job.Config{
      name: :first_job,
      objective: "to create a sequence of steps",
      steps: [
        %Job.Step{
          agent: :first_agent,
          prompt: "",
          conditions: nil
        },
        %Job.Step{
          agent: :second_agent,
          prompt: "",
          conditions: nil
        },
        %Job.Step{
          agent: :verifier_agent,
          prompt: "",
          conditions: %{
            "TRUE" => :end,
            "__DEFAULT__" => 0
          }
        }
      ]
    }

    {:ok, pid} = Agens.start_job(job)

    [
      job: job,
      pid: pid
    ]
  end

  describe "job" do
    test "config", %{job: job, pid: pid} do
      assert is_pid(pid)
      assert job == Job.get_config(pid)
      assert job == Job.get_config(:first_job)
      assert {:error, :job_not_found} == Job.get_config(:missing_job)
    end

    test "start", %{job: %{name: name}, pid: pid} do
      input = "D"
      assert is_pid(pid)
      result = Agens.Job.start(name, input)

      assert result == :ok
      assert_receive {:job_started, ^name}

      # 0
      assert_receive {:step_started, ^name, 0, "D"}
      assert_receive {:step_result, ^name, 0, "C"}
      assert_receive {:step_started, ^name, 1, "C"}
      assert_receive {:step_result, ^name, 1, "E"}
      assert_receive {:step_started, ^name, 2, "E"}
      assert_receive {:step_result, ^name, 2, "FALSE"}

      # 1
      assert_receive {:step_started, ^name, 0, "E"}
      assert_receive {:step_result, ^name, 0, "D"}
      assert_receive {:step_started, ^name, 1, "D"}
      assert_receive {:step_result, ^name, 1, "F"}
      assert_receive {:step_started, ^name, 2, "F"}
      assert_receive {:step_result, ^name, 2, "FALSE"}

      # 2
      assert_receive {:step_started, ^name, 0, "F"}
      assert_receive {:step_result, ^name, 0, "E"}
      assert_receive {:step_started, ^name, 1, "E"}
      assert_receive {:step_result, ^name, 1, "G"}
      assert_receive {:step_started, ^name, 2, "G"}
      assert_receive {:step_result, ^name, 2, "TRUE"}

      assert_receive {:job_ended, ^name, :complete}
    end
  end
end
