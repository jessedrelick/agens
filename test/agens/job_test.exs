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

  describe "restart" do
    @tag capture_log: true
    test "crash" do
      name = :crash_job

      job = %Job.Config{
        name: name,
        objective: "to simulate a crash",
        steps: [
          %Job.Step{
            agent: :first_agent,
            prompt: "",
            conditions: nil
          },
          %Job.Step{
            agent: :verifier_agent,
            prompt: "",
            conditions: %{
              "TRUE" => :end,
              "__DEFAULT__" => :invalid
            }
          }
        ]
      }

      {:ok, pid} = Agens.start_job(job)

      input = "F"
      assert is_pid(pid)
      result = Agens.Job.start(name, input)
      assert result == :ok
      assert_receive {:job_started, ^name}

      assert_receive {:step_started, ^name, 0, "F"}
      assert_receive {:step_result, ^name, 0, "E"}
      assert_receive {:step_started, ^name, 1, "E"}
      assert_receive {:step_result, ^name, 1, "FALSE"}

      assert_receive {:job_ended, ^name,
                      {:error, %RuntimeError{message: "Invalid step index: :invalid"}}}

      Process.sleep(100)
      refute Process.alive?(pid)

      new_pid = GenServer.whereis(name)
      assert is_pid(new_pid)
      refute pid == new_pid
      assert Process.alive?(new_pid)

      result = Agens.Job.start(name, input)
      assert result == :ok
      assert_receive {:job_started, ^name}
    end
  end

  describe "tool use" do
    test "noop tool" do
      name = :noop_job

      job = %Job.Config{
        name: name,
        objective: "to test tool usage",
        steps: [
          %Job.Step{
            agent: :first_agent,
            prompt: "",
            conditions: nil
          },
          %Job.Step{
            agent: :tool_agent,
            prompt: "",
            conditions: %{
              "TRUE" => :end,
              "__DEFAULT__" => 0
            }
          }
        ]
      }

      {:ok, pid} = Agens.start_job(job)

      input = "F"
      assert is_pid(pid)
      result = Agens.Job.start(name, input)
      assert result == :ok
      assert_receive {:job_started, ^name}

      assert_receive {:step_started, ^name, 0, "F"}
      assert_receive {:step_result, ^name, 0, "E"}
      assert_receive {:step_started, ^name, 1, "E"}
      # assert_receive {:tool_started, ^name, 1, "FALSE"}
      # assert_receive {:tool_raw, ^name, 1, %{}}
      # assert_receive {:tool_result, ^name, 1, "TRUE"}
      assert_receive {:step_result, ^name, 1, "TRUE"}

      assert_receive {:job_ended, ^name, :complete}
    end
  end
end
