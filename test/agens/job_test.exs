defmodule Agens.JobTest do
  use Test.Support.AgentCase, async: true

  alias Agens.{Agent, Job, Message, Serving}

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

  defp start_job(_ctx) do
    get_agent_configs()
    |> Agent.start()

    job = %Job.Config{
      name: :first_job,
      description: "to create a sequence of steps",
      steps: [
        %Job.Step{
          agent: :first_agent,
          objective: "test step objective",
          conditions: nil
        },
        %Job.Step{
          agent: :second_agent,
          conditions: nil
        },
        %Job.Step{
          agent: :verifier_agent,
          conditions: %{
            "TRUE" => :end,
            "__DEFAULT__" => 0
          }
        }
      ]
    }

    {:ok, pid} = Job.start(job)

    [
      job: job,
      pid: pid
    ]
  end

  describe "config" do
    setup :start_agens

    test "config" do
      job = %Job.Config{
        name: :job_config,
        steps: []
      }

      {:ok, pid} = Job.start(job)

      assert is_pid(pid)
      assert job == Job.get_config(pid)
      assert job == Job.get_config(:job_config)
      assert {:error, :job_not_found} == Job.get_config(:missing_job)
    end
  end

  # describe "job" do
  #   setup :start_job

  #   @tag capture_log: true
  #   test "start", %{job: %{name: name}, pid: pid} do
  #     input = "D"

  #     assert is_pid(pid)
  #     assert Job.run(name, input) == :ok

  #     assert_receive {:job_started, ^name}

  #     # 0
  #     assert_receive {:step_started, {^name, 0}, "D"}
  #     assert_receive {:step_result, {^name, 0}, "C"}
  #     assert_receive {:step_started, {^name, 1}, "C"}
  #     assert_receive {:step_result, {^name, 1}, "E"}
  #     assert_receive {:step_started, {^name, 2}, "E"}
  #     assert_receive {:step_result, {^name, 2}, "E"}

  #     # 1
  #     assert_receive {:step_started, {^name, 0}, "E"}
  #     assert_receive {:step_result, {^name, 0}, "D"}
  #     assert_receive {:step_started, {^name, 1}, "D"}
  #     assert_receive {:step_result, {^name, 1}, "F"}
  #     assert_receive {:step_started, {^name, 2}, "F"}
  #     assert_receive {:step_result, {^name, 2}, "F"}

  #     # 2
  #     assert_receive {:step_started, {^name, 0}, "F"}
  #     assert_receive {:step_result, {^name, 0}, "E"}
  #     assert_receive {:step_started, {^name, 1}, "E"}
  #     assert_receive {:step_result, {^name, 1}, "G"}
  #     assert_receive {:step_started, {^name, 2}, "G"}
  #     assert_receive {:step_result, {^name, 2}, "TRUE"}

  #     assert_receive {:job_ended, ^name, :complete}
  #   end
  # end

  describe "restart" do
    setup [:start_agens, :start_serving]

    @tag capture_log: true
    @tag :skip
    test "crash" do
      name = :crash_job

      [
        %Agent.Config{
          name: :first_agent,
          serving: :text_generation
        },
        %Agent.Config{
          name: :verifier_agent,
          serving: :text_generation
        }
      ]
      |> Agent.start()

      job = %Job.Config{
        name: name,
        description: "to simulate a crash",
        steps: [
          %Job.Step{
            agent: :first_agent
          },
          %Job.Step{
            agent: :verifier_agent,
            conditions: %{
              "TRUE" => :end,
              "__DEFAULT__" => :invalid
            }
          }
        ]
      }

      {:ok, pid} = Job.start(job)

      input = "F"
      assert is_pid(pid)
      result = Job.run(name, input)
      assert result == :ok
      assert_receive {:job_started, ^name}

      assert_receive {:step_started, {^name, 0}, "F"}
      assert_receive {:step_result, {^name, 0}, "E"}
      assert_receive {:step_started, {^name, 1}, "E"}
      assert_receive {:step_result, {^name, 1}, "FALSE"}

      assert_receive {:job_ended, ^name,
                      {:error, %RuntimeError{message: "Invalid step index: :invalid"}}}

      Process.sleep(100)
      refute Process.alive?(pid)

      new_pid = GenServer.whereis(name)
      assert is_pid(new_pid)
      refute pid == new_pid
      assert Process.alive?(new_pid)

      result = Job.run(name, input)
      assert result == :ok
      assert_receive {:job_started, ^name}
    end
  end

  describe "tool use" do
    setup [:start_agens, :start_serving, :start_job]

    @tag capture_log: true
    test "noop tool" do
      name = :noop_job

      job = %Job.Config{
        name: name,
        description: "to test tool usage",
        steps: [
          %Job.Step{
            agent: :first_agent,
            objective: "",
            conditions: nil
          },
          %Job.Step{
            agent: :tool_agent,
            conditions: %{
              "TRUE" => :end,
              "__DEFAULT__" => 0
            }
          }
        ]
      }

      {:ok, pid} = Job.start(job)

      input = "F"
      assert is_pid(pid)
      result = Job.run(name, input)
      assert result == :ok
      assert_receive {:job_started, ^name}

      assert_receive {:step_started, {^name, 0}, "F"}
      assert_receive {:step_result, {^name, 0}, "E"}
      assert_receive {:step_started, {^name, 1}, "E"}
      assert_receive {:tool_started, {^name, 1}, "FALSE"}
      assert_receive {:tool_raw, {^name, 1}, %{}}
      assert_receive {:tool_result, {^name, 1}, "TRUE"}
      assert_receive {:step_result, {^name, 1}, "TRUE"}

      assert_receive {:job_ended, ^name, :complete}
    end
  end

  describe "prompt" do
    setup [:start_agens, :start_serving]

    @tag :skip
    test "full prompt" do
      job_name = :test_prompt_job
      agent_name = :test_prompt_agent
      input = "test input"

      prompt = %Agent.Prompt{
        identity: "test agent identity",
        constraints: "test agent constraints",
        context: "test agent context",
        reflection: "test agent reflection"
        # examples: [
        #   %{input: "A", output: "C"},
        #   %{input: "F", output: "H"},
        #   %{input: "9vasg2rwe", output: "ERROR"}
        # ],
      }

      %Agent.Config{
        name: agent_name,
        serving: :text_generation,
        prompt: prompt,
        tool: NoopTool
      }
      |> Agent.start()

      %Job.Config{
        name: job_name,
        description: "test job description",
        steps: [
          %Job.Step{
            agent: agent_name,
            objective: "test step objective",
            conditions: %{
              "__DEFAULT__" => :end
            }
          }
        ]
      }
      |> Job.start()

      Job.run(job_name, input)

      assert_receive {:job_started, ^job_name}

      assert_receive {:step_started, {^job_name, 0}, "test input"}
      assert_receive {:tool_started, {^job_name, 0}, "STUB RUN"}
      assert_receive {:tool_raw, {^job_name, 0}, %{}}
      assert_receive {:tool_result, {^job_name, 0}, "TRUE"}
      assert_receive {:step_result, {^job_name, 0}, "TRUE"}
      assert_receive {:job_ended, ^job_name, :complete}
    end
  end

  describe "lm" do
    @tag :lm
    test "run job" do
      {:ok, pid} =
        %Agens.Serving.Config{
          name: :text_generation_lm,
          serving: Test.Support.Serving.LLM.get()
        }
        |> Agens.Serving.start()

      assert is_pid(pid)
    end
  end
end
