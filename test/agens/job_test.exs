defmodule Agens.JobTest do
  use Test.Support.AgentCase, async: true
  doctest Agens

  alias Agens.Job

  describe "job" do
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
