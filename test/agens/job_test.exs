defmodule Agens.JobTest do
  use ExUnit.Case, async: false

  alias Agens.{Job, Message, Prefixes, Resource}
  alias Agens.Job.Yield
  alias Test.Support.{Resources, Tools}

  defp start_agens(_ctx) do
    {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})
    :ok
  end

  defp start_serving(_ctx) do
    %Agens.Serving.Config{
      name: :test_serving,
      serving: Test.Support.Serving
    }
    |> Agens.Serving.start()

    %Agens.Serving.Config{
      name: :sub_routing_serving,
      serving: Test.Support.SubRoutingServing
    }
    |> Agens.Serving.start()

    :ok
  end

  defp start_job(_ctx) do
    job = %Job.Config{
      id: "first_job",
      starting_node_id: "node_0",
      description: "to create a sequence of nodes",
      nodes: %{
        "node_0" => %Job.Node{
          serving: :test_serving,
          agent_id: "first_agent",
          objective: "test node objective"
        },
        "node_10" => %Job.Node{
          serving: :test_serving,
          agent_id: "second_agent"
        },
        "node_20" => %Job.Node{
          serving: :test_serving,
          agent_id: "verifier_agent"
        }
      }
    }

    run_id = "start_job_run_id"
    {:ok, pid} = Job.start(job, run_id)

    [
      job: job,
      pid: pid,
      run_id: run_id
    ]
  end

  describe "errors" do
    setup [:start_agens, :start_serving, :start_job]

    test "already started", %{job: job, pid: pid, run_id: run_id} do
      {:error, {:already_started, ^pid}} = Job.start(job, run_id)
      assert is_pid(pid)
    end

    test "job not found" do
      assert {:error, :run_not_found} == Job.run("nonexistent_run_id", "input", [])
    end

    test "job already running", %{run_id: run_id} do
      input = "input"

      :ok = Job.run(run_id, input, [])
      assert {:error, :job_already_running} == Job.run(run_id, input, [])
    end

    test "nil input", %{run_id: run_id} do
      assert {:error, :input_required} == Job.run(run_id, nil, [])
    end

    test "invalid node id" do
      input = "input"
      node_id = "invalid_node_id"
      caller = self()
      id = "invalid_node_job"
      run_id = "invalid_node_run_id"
      description = "to test invalid node"

      job = %Job.Config{
        id: id,
        starting_node_id: node_id,
        description: description,
        nodes: %{
          "node_0" => %Job.Node{serving: :test_serving, agent_id: "first_agent"}
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      assert_receive {:job_error,
                      %Message{
                        job_id: ^id,
                        job_description: ^description,
                        run_id: ^run_id,
                        input: ^input,
                        node_id: ^node_id,
                        caller: ^caller
                      }, :invalid_node}
    end

    test "invalid next value", %{job: %{id: id, description: description}, run_id: run_id} do
      input = "invalid next"
      caller = self()
      next = "invalid next node"

      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: "first_agent",
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "first_agent",
                        node_id: "node_0",
                        input: ^input,
                        result: "invalid next test",
                        next: ^next
                      }}

      assert_receive {:job_error,
                      %Message{
                        job_id: ^id,
                        job_description: ^description,
                        run_id: ^run_id,
                        input: ^input,
                        node_id: "node_0",
                        caller: ^caller,
                        next: ^next
                      }, :invalid_next}
    end
  end

  describe "config" do
    setup :start_agens

    test "config - by job id" do
      job = %Job.Config{
        id: "job_config",
        starting_node_id: "node_0",
        nodes: []
      }

      {:ok, pid} = Job.start(job, "job_config_run_id")

      assert is_pid(pid)
      assert {:ok, job} == Job.get_config(pid)
      assert {:error, :run_not_found} == Job.get_config("missing_job")
    end

    test "config - by run id" do
      run_id = "run_id_123abc"

      job = %Job.Config{
        id: "job_config",
        starting_node_id: "node_0",
        nodes: []
      }

      {:ok, pid} = Job.start(job, run_id)

      assert is_pid(pid)
      assert {:ok, job} == Job.get_config(pid)
      assert {:ok, job} == Job.get_config(run_id)
      assert {:error, :run_not_found} == Job.get_config(job.id)
    end
  end

  describe "sequence" do
    setup [:start_agens, :start_serving, :start_job]

    test "start with run id", %{job: %{id: id} = job} do
      input = "F"
      run_id = "test_run_id"

      {:ok, pid} = Job.start(job, run_id)

      assert is_pid(pid)
      {:error, {:already_started, ^pid}} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      # Agent 1
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "first_agent",
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "first_agent",
                        node_id: "node_0",
                        input: ^input,
                        result: "E",
                        previous_result: nil,
                        next: [{:route, "node_10", 1}]
                      }}

      # Agent 2
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "second_agent",
                        node_id: "node_10",
                        input: ^input,
                        previous_result: "E"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "second_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: "G",
                        previous_result: "E",
                        next: [{:route, "node_20", 1}]
                      }}

      # Agent 3
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "verifier_agent",
                        node_id: "node_20",
                        input: ^input,
                        previous_result: "G"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "verifier_agent",
                        node_id: "node_20",
                        input: ^input,
                        result: "TRUE",
                        previous_result: "G",
                        next: [:end]
                      }}

      # END
      assert_receive {:job_status, {^run_id, :running}}
      assert_receive {:job_ended, ^run_id}
    end
  end

  describe "parallel" do
    setup [:start_agens, :start_serving]

    test "multiple threads" do
      input = "H"
      id = "parallel_job"
      run_id = "test_parallel_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to execute multiple agents in parallel",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "parallel_agent",
            objective: "test fan out"
          },
          "node_10" => %Job.Node{
            serving: :test_serving,
            agent_id: "default_agent",
            objective: "test parallel execution"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      # Fan out
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "parallel_agent",
                        node_id: "node_0",
                        input: "H"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "parallel_agent",
                        node_id: "node_0",
                        input: ^input,
                        result: ^input,
                        next: [{:route, "node_10", 4}]
                      }}

      assert_receive {:prompt, _prompt}
      assert_receive {:job_status, {^run_id, :running}}

      # Parallel (4x)
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: "H",
                        thread_id: thread_id_1
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: "H",
                        thread_id: thread_id_2
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: "H",
                        thread_id: thread_id_3
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: "H",
                        thread_id: thread_id_4
                      }}

      assert is_binary(thread_id_1)
      assert is_binary(thread_id_2)
      assert is_binary(thread_id_3)
      assert is_binary(thread_id_4)
      threads = [thread_id_1, thread_id_2, thread_id_3, thread_id_4]
      assert Enum.uniq(threads) |> length() == 4

      assert_receive {:prompt, _prompt}
      assert_receive {:prompt, _prompt}
      assert_receive {:prompt, _prompt}
      # assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: "sent 'H' to: default_agent",
                        thread_id: thread_1,
                        next: []
                      }}

      threads = List.delete(threads, thread_1)

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: "sent 'H' to: default_agent",
                        thread_id: thread_2,
                        next: []
                      }}

      threads = List.delete(threads, thread_2)

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: "sent 'H' to: default_agent",
                        thread_id: thread_3,
                        next: []
                      }}

      threads = List.delete(threads, thread_3)

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "default_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: "sent 'H' to: default_agent",
                        thread_id: thread_4,
                        next: []
                      }}

      threads = List.delete(threads, thread_4)
      assert length(threads) == 0

      assert_receive {:job_complete, ^run_id}
    end
  end

  describe "retries" do
    setup [:start_agens, :start_serving]

    test "max retries" do
      input = "error"
      id = "retries_job"
      run_id = "test_retries_run_id"
      agent_id = "retry_agent"
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test retries",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: agent_id,
            objective: "test retry node"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        retries: 0,
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}

      refute user =~ retry_prefix

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input,
                        result: nil,
                        next: []
                      }}

      assert_receive {:prompt, {_system, user}}

      assert user =~ retry_prefix

      assert_receive {:node_retry,
                      %Message{
                        retries: 2,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input,
                        result: nil,
                        next: []
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_retry,
                      %Message{
                        retries: 3,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input,
                        result: nil,
                        next: []
                      }}

      assert_receive {:job_error,
                      %Message{
                        retries: 3,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input,
                        result: nil,
                        next: []
                      }, :max_retries}
    end

    test "explict retry" do
      input = "explicit"
      id = "retries_job"
      run_id = "test_explicit_retry_run_id"
      result = "explicit retry"
      agent_id = "retry_agent"
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test explicit retries",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: agent_id,
            objective: "test explicit retry node"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        retries: 0,
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}

      refute user =~ retry_prefix

      assert_receive {:node_result, %Message{}}

      assert_receive {:node_retry,
                      %Message{
                        next: [:retry],
                        retries: 1,
                        retry_reason: nil,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input,
                        result: ^result
                      }}

      assert_receive {:prompt, {_system, user}}

      assert user =~ retry_prefix

      assert_receive {:node_result, %Message{}}

      assert_receive {:node_started, %Message{}}

      # assert_receive {:node_retry,
      #                 %Message{
      #                   retries: 2,
      #                   job_id: ^name,
      #                   agent_id: ^agent_id,
      #                   node_id: "node_0",
      #                   input: ^input,
      #                   result: nil,
      #                   next: nil
      #                 }}

      # assert_receive {:prompt, _prompt}

      # assert_receive {:node_retry,
      #                 %Message{
      #                   retries: 3,
      #                   job_id: ^name,
      #                   agent_id: ^agent_id,
      #                   node_id: "node_0",
      #                   input: ^input,
      #                   result: nil,
      #                   next: nil
      #                 }}

      # assert_receive {:job_error,
      #                 %Message{
      #                   retries: 3,
      #                   job_id: ^name,
      #                   agent_id: ^agent_id,
      #                   node_id: "node_0",
      #                   input: ^input,
      #                   result: nil,
      #                   next: nil
      #                 }, :max_retries}
    end

    test "config max retries" do
      input = "error"
      id = "retries_job"
      run_id = "test_retries_config_run_id"
      agent_id = "retry_agent"
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to override max retries",
        max_retries: 1,
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: agent_id,
            objective: "test retry node"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        retries: 0,
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}

      refute user =~ retry_prefix

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input,
                        result: nil,
                        next: []
                      }}

      assert_receive {:prompt, {_system, user}}

      assert user =~ retry_prefix

      assert_receive {:job_error,
                      %Message{
                        retries: 1,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: "node_0",
                        input: ^input,
                        result: nil,
                        next: []
                      }, :max_retries}
    end

    test "retry with reason from serving" do
      input = "error"
      id = "retries_job"
      run_id = "test_retry_reason_run_id"
      agent_id = "retry_agent"
      retry_reason = "validation error"
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test retry reason from serving",
        max_retries: 1,
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: agent_id,
            objective: "test retry reason node"
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      assert_receive {:node_started, %Message{retries: 0}}

      assert_receive {:prompt, {_system, user}}
      refute user =~ retry_prefix

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        retry_reason: ^retry_reason,
                        job_id: ^id,
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}
      assert user =~ retry_prefix
      assert user =~ retry_reason

      assert_receive {:job_error, %Message{retries: 1}, :max_retries}
    end

    test "retry with reason from next" do
      input = "explicit_with_reason"
      id = "retries_job"
      run_id = "test_retry_reason_next_run_id"
      agent_id = "retry_agent"
      retry_reason = "LLM provided reason"
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test retry reason from next",
        max_retries: 1,
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: agent_id,
            objective: "test retry reason from next node"
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      assert_receive {:node_started, %Message{retries: 0}}

      assert_receive {:prompt, {_system, user}}
      refute user =~ retry_prefix

      assert_receive {:node_result, %Message{}}

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        retry_reason: ^retry_reason,
                        job_id: ^id,
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}
      assert user =~ retry_prefix
      assert user =~ retry_reason

      assert_receive {:job_error, %Message{retries: 1}, :max_retries}
    end

    test "error terminates immediately" do
      input = "fatal"
      id = "retries_job"
      run_id = "test_error_terminates_run_id"
      agent_id = "retry_agent"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test error terminates",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: agent_id,
            objective: "test error terminates node"
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      assert_receive {:node_started, %Message{retries: 0}}

      assert_receive {:job_error, %Message{retries: 0, node_id: "node_0"}, :fatal_error}

      refute_receive {:node_retry, %Message{}}
    end
  end

  describe "end" do
    setup [:start_agens, :start_serving]

    test "ends job immediately" do
      input = "input"
      id = "end_job"
      run_id = "test_end_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to end job",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "end_agent",
            objective: "test end node"
          },
          "node_10" => %Job.Node{
            serving: :test_serving,
            agent_id: "first_agent",
            objective: "noop"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, _prompt}
      assert_receive {:node_result, %Message{next: [:end]}}

      assert_receive {:job_ended, ^run_id}
    end
  end

  describe "restart" do
    setup [:start_agens, :start_serving]

    test "crash" do
      input = "unhandled exception"
      id = "crash_job"
      run_id = "crash_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to simulate a crash",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "error_agent"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, _prompt}

      # TODO: handle exception "bubbling"
      # ref = Process.monitor(pid)
      # assert_receive {:job_error, {^name, 1},
      #                 {:error, %RuntimeError{message: "Invalid node index: :invalid"}}}

      # assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
      # Process.demonitor(ref)
      # refute Process.alive?(pid)

      # TODO: alternative to Process.sleep/1?
      # custom send from start_link/1 or init/1: 'from' not available
      # supervisor: does not send any message when restarting child
      # monitor: only notifies of terminated process
      # Process.sleep(100)
      # new_pid = GenServer.whereis(name)
      # assert is_pid(new_pid)
      # refute pid == new_pid
      # assert Process.alive?(new_pid)

      # result = Job.run(name, input, "node_id", nil)
      # assert result == :ok
      # assert_receive {:job_run, ^name}
    end
  end

  describe "tools" do
    setup [:start_agens, :start_serving, :start_job]

    test "tool" do
      input = "T"
      id = "test_tool_job"
      run_id = "test_tool_run_id"
      tool_name = "test_tool_name"
      tool_call_id = "tool_call_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test tool usage",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "tool_agent",
            objective: "agent for testing tools",
            tools: [
              Tools.tool_def()
            ]
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)

      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, _prompt}

      assert_receive {:tool_call, %Message{run_id: ^run_id},
                      %{tool: %{name: ^tool_name, arguments: _, result: _}, error: _}}

      assert_receive {:node_result, %Message{tool_results: tool_results}}
      result = Map.get(tool_results, tool_call_id)

      assert result == "tool result for: #{tool_call_id}"

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, _prompt}
      # assert_receive {:node_result, %Message{}}
      # assert_receive {:job_complete, ^run_id}
    end

    test "tool errors surface in :tool_call backend events" do
      input = "T"
      id = "test_tool_error_job"
      run_id = "test_tool_error_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "tool_error_agent",
            tools: [Tools.tool_def()]
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, [])

      assert_receive {:tool_call, %Message{run_id: ^run_id},
                      %{tool: %{name: "outer_error_tool", result: nil}, error: outer_error}}

      assert outer_error =~ "outer_failed"

      assert_receive {:tool_call, %Message{run_id: ^run_id},
                      %{tool: %{name: "inner_error_tool", result: nil}, error: inner_error}}

      assert inner_error =~ "inner_failed"
    end
  end

  describe "resources" do
    setup [:start_agens, :start_serving]

    test "resource content is loaded and appears in system prompt" do
      id = "test_resource_job"
      run_id = "test_resource_run_id"
      resource = Resources.resource_def()

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test resource loading",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "resource_agent",
            objective: "agent for testing resources",
            resources: [resource]
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:node_started, %Message{resources: [%Resource{content: nil}]}}
      assert_receive {:prompt, {system, _user}}

      expected_content = Resources.resource_content(resource.uri)
      assert system =~ "### #{resource.uri}"
      assert system =~ expected_content
      assert system =~ "## Resources"
    end

    test "resource with no content is excluded from prompt" do
      id = "test_resource_no_content_job"
      run_id = "test_resource_no_content_run_id"
      resource = Resources.resource_def(:no_content)

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "resource_agent",
            resources: [resource]
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", [])

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, {system, _user}}

      refute system =~ "### #{resource.uri}"
      refute system =~ "## Resources"
    end

    test "multiple resources load in parallel and all appear in prompt" do
      id = "test_multi_resource_job"
      run_id = "test_multi_resource_run_id"
      resource = Resources.resource_def()

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "resource_agent",
            resources: [resource, resource]
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", [])

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, {system, _user}}

      expected_content = Resources.resource_content(resource.uri)
      assert String.count(system, expected_content) == 2
    end

    test "node without resources sends prompt with no resource section" do
      id = "test_no_resource_job"
      run_id = "test_no_resource_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "resource_agent"
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", [])

      assert_receive {:node_started, %Message{resources: nil}}
      assert_receive {:prompt, {system, _user}}

      refute system =~ "Resources"
    end
  end

  describe "prompt" do
    setup [:start_agens, :start_serving]

    test "standard prompt" do
      job_id = "test_prompt_job"
      run_id = "test_prompt_run_id"
      agent_id = "test_prompt_agent"
      input = "test input"
      job_description = "test job description"
      node_objective = "test node objective"

      %{
        description: {description_heading, description_prompt},
        objective: {objective_heading, objective_prompt},
        input: {input_heading, input_prompt}
      } = Prefixes.default()

      standard_system = """
      ## #{description_heading}\n#{description_prompt}:\n\n#{job_description}\n
      ## #{objective_heading}\n#{objective_prompt}:\n\n#{node_objective}
      """

      standard_user = """
      ## #{input_heading}\n#{input_prompt}:\n\n#{input}
      """

      {:ok, _pid} =
        %Job.Config{
          id: job_id,
          starting_node_id: "node_0",
          description: job_description,
          nodes: %{
            "node_0" => %Job.Node{
              serving: :test_serving,
              agent_id: agent_id,
              objective: node_objective
            }
          }
        }
        |> Job.start(run_id)

      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^job_id, ^run_id}

      assert_receive {:node_started,
                      %Message{node_objective: ^node_objective, job_description: ^job_description}}

      assert_receive {:prompt, {system, user}}
      assert system == standard_system
      assert user == standard_user
      assert_receive {:node_result, %Message{}}
      assert_receive {:job_complete, ^run_id}
    end
  end

  describe "yield" do
    setup [:start_agens, :start_serving]

    test "waits until all threads are ready" do
      input = "Y"
      id = "yield_job"
      run_id = "test_yield_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to yield and aggregate results",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "split_agent",
            objective: "test split node objective"
          },
          "node_10" => %Job.Node{
            serving: :test_serving,
            agent_id: "concurrent_agent",
            objective: "test concurrent node objective"
          },
          "node_20" => %Job.Node{
            serving: :test_serving,
            agent_id: "yield_agent",
            objective: "test yield node objective"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      # Fan out
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "split_agent",
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "split_agent",
                        node_id: "node_0",
                        input: ^input,
                        result: ^input,
                        next: [{:route, "node_10", 4}]
                      }}

      assert_receive {:prompt, _prompt}
      assert_receive {:prompt, _prompt}
      assert_receive {:prompt, _prompt}
      assert_receive {:prompt, _prompt}

      # # Parallel (4x)
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        thread_id: thread_id_1
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        thread_id: thread_id_2
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        thread_id: thread_id_3
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        thread_id: thread_id_4
                      }}

      assert is_binary(thread_id_1)
      assert is_binary(thread_id_2)
      assert is_binary(thread_id_3)
      assert is_binary(thread_id_4)
      threads = [thread_id_1, thread_id_2, thread_id_3, thread_id_4]
      assert Enum.uniq(threads) |> length() == 4

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: ^input,
                        thread_id: thread_1,
                        next: [{:yield, "node_20"}]
                      }}

      threads = List.delete(threads, thread_1)

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: ^input,
                        thread_id: thread_2,
                        next: [{:yield, "node_20"}]
                      }}

      threads = List.delete(threads, thread_2)

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: ^input,
                        thread_id: thread_3,
                        next: [{:yield, "node_20"}]
                      }}

      threads = List.delete(threads, thread_3)

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "concurrent_agent",
                        node_id: "node_10",
                        input: ^input,
                        result: ^input,
                        thread_id: thread_4,
                        next: [{:yield, "node_20"}]
                      }}

      threads = List.delete(threads, thread_4)
      assert length(threads) == 0

      assert_receive {:yield_wait, {%Message{}, 4, 1}}
      assert_receive {:yield_wait, {%Message{}, 4, 2}}
      assert_receive {:yield_wait, {%Message{}, 4, 3}}
      assert_receive {:yield_done, {%Message{}, 4}}

      assert_receive {:node_started,
                      %Message{
                        agent_id: "yield_agent",
                        node_id: "node_20",
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "yield_agent",
                        node_id: "node_20",
                        input: ^input,
                        result: ^input,
                        next: []
                      }}

      assert_receive {:job_complete, ^run_id}
    end
  end

  describe "sub" do
    setup [:start_agens, :start_serving]

    test "route instruction" do
      input = "S"
      id = "sub_job"
      run_id = "test_sub_run_id"
      sub_id = "sub"
      sub_run_id = "sub_run_id"
      sub_first_node_id = "sub_node_0"
      sub_final_agent = "sub_final_agent"
      sub_result = "sent '#{input}' to: #{sub_final_agent}"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to spawn a sub job via route instruction",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: "sub_agent",
            objective: "test sub job"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}
      assert_receive {:prompt, _prompt}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: "sub_agent",
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: "sub_agent",
                        node_id: "node_0",
                        input: ^input,
                        result: ^input,
                        next: [{:sub, "sub_job"}]
                      }}

      # Sub Job
      assert_receive {:job_run, ^sub_id, ^sub_run_id}
      assert_receive {:job_status, {^sub_run_id, :running}}
      assert_receive {:prompt, _prompt}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^sub_id,
                        run_id: ^sub_run_id,
                        parent_run_id: ^run_id,
                        agent_id: ^sub_final_agent,
                        node_id: ^sub_first_node_id,
                        input: ^input
                      }}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^sub_id,
                        agent_id: ^sub_final_agent,
                        node_id: ^sub_first_node_id,
                        input: ^input,
                        result: ^sub_result,
                        next: []
                      }}

      assert_receive {:job_complete, ^sub_run_id}
      assert_receive {:job_complete, ^run_id}
      refute_receive {:node_result, %Message{job_id: ^id, node_id: "node_0", result: ^sub_result}}
    end

    test "node sub" do
      input = "S"
      id = "sub_job"
      run_id = "test_sub_run_id"
      sub_id = "sub"
      sub_run_id = "sub_run_id"
      sub_first_node_id = "sub_node_0"
      sub_final_agent = "sub_final_agent"
      sub_result = "sent '#{input}' to: #{sub_final_agent}"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to spawn a sub job via node sub field",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            sub: sub_id,
            objective: "test sub job"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}
      assert_receive {:prompt, _prompt}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        node_id: "node_0",
                        input: ^input
                      }}

      # Sub Job
      assert_receive {:job_run, ^sub_id, ^sub_run_id}
      assert_receive {:job_status, {^sub_run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^sub_id,
                        run_id: ^sub_run_id,
                        parent_run_id: ^run_id,
                        agent_id: ^sub_final_agent,
                        node_id: ^sub_first_node_id,
                        input: ^input
                      }}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^sub_id,
                        agent_id: ^sub_final_agent,
                        node_id: ^sub_first_node_id,
                        input: ^input,
                        result: ^sub_result,
                        next: []
                      }}

      assert_receive {:job_complete, ^sub_run_id}

      # Finish Parent
      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: nil,
                        node_id: "node_0",
                        input: ^input,
                        result: ^sub_result
                      }}

      assert_receive {:job_complete, ^run_id}
    end

    test "node sub with subsequent node" do
      input = "S"
      id = "sub_job"
      run_id = "test_sub_run_id"
      sub_id = "sub"
      sub_run_id = "sub_run_id"
      sub_first_node_id = "sub_node_0"
      sub_final_agent = "sub_final_agent"
      sub_result = "sent '#{input}' to: #{sub_final_agent}"
      next_agent = "post_sub_agent"
      next_result = "sent '#{sub_result}' to: #{next_agent}"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to spawn a sub job and then execute a subsequent node",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :sub_routing_serving,
            sub: sub_id
          },
          "node_1" => %Job.Node{
            serving: :test_serving,
            agent_id: next_agent
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}
      assert_receive {:prompt, _prompt}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        node_id: "node_0",
                        input: ^input
                      }}

      # Sub Job
      assert_receive {:job_run, ^sub_id, ^sub_run_id}
      assert_receive {:job_status, {^sub_run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^sub_id,
                        run_id: ^sub_run_id,
                        parent_run_id: ^run_id,
                        agent_id: ^sub_final_agent,
                        node_id: ^sub_first_node_id,
                        input: ^input
                      }}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^sub_id,
                        agent_id: ^sub_final_agent,
                        node_id: ^sub_first_node_id,
                        input: ^input,
                        result: ^sub_result,
                        next: []
                      }}

      assert_receive {:job_complete, ^sub_run_id}

      # Parent node_0 result with sub's output
      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: nil,
                        node_id: "node_0",
                        input: ^input,
                        result: ^sub_result
                      }}

      # Subsequent node_1 runs after sub completes
      assert_receive {:prompt, _prompt}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        node_id: "node_1",
                        agent_id: ^next_agent,
                        input: ^input
                      }}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        node_id: "node_1",
                        agent_id: ^next_agent,
                        result: ^next_result
                      }}

      assert_receive {:job_complete, ^run_id}

      refute_receive {:job_complete, ^run_id}
    end
  end

  # ===========================================================================
  # Parsing
  # ===========================================================================

  describe "Node.from_map/1" do
    test "builds a Node from a complete string-keyed map" do
      map = %{
        "serving" => "test_serving",
        "agent_id" => "my_agent",
        "sub" => "some_sub",
        "objective" => "test objective",
        "tools" => ["tool_schema"],
        "resources" => [%{"uri" => "test://res", "name" => "My Resource"}]
      }

      node = Job.Node.from_map(map)

      assert node.serving == :test_serving
      assert node.agent_id == "my_agent"
      assert node.sub == "some_sub"
      assert node.objective == "test objective"
      assert node.tools == ["tool_schema"]
      assert [%Resource{uri: "test://res", name: "My Resource"}] = node.resources
    end

    test "handles nil serving and missing optional fields" do
      node = Job.Node.from_map(%{"agent_id" => "bare_agent"})

      assert node.serving == nil
      assert node.agent_id == "bare_agent"
      assert node.sub == nil
      assert node.resources == nil
    end
  end

  describe "Config.from_map/1" do
    test "builds a Config from a string-keyed map" do
      map = %{
        "id" => "parsed_job",
        "description" => "test description",
        "starting_node_id" => "node_0",
        "max_retries" => 2,
        "nodes" => %{
          "node_0" => %{
            "serving" => "test_serving",
            "agent_id" => "my_agent",
            "objective" => "test node"
          }
        }
      }

      config = Job.Config.from_map(map)

      assert config.id == "parsed_job"
      assert config.description == "test description"
      assert config.starting_node_id == "node_0"
      assert config.max_retries == 2
      node = config.nodes["node_0"]
      assert node.serving == :test_serving
      assert node.agent_id == "my_agent"
    end

    test "defaults max_retries to 3 when not provided" do
      map = %{
        "id" => "default_retries_job",
        "starting_node_id" => "node_0",
        "nodes" => %{}
      }

      config = Job.Config.from_map(map)

      assert config.max_retries == 3
    end
  end

  describe "Config.from_json/1" do
    test "parses a valid JSON string into a Config" do
      json =
        ~s({"id":"json_job","starting_node_id":"node_0","nodes":{"node_0":{"serving":"test_serving","agent_id":"json_agent"}}})

      config = Job.Config.from_json(json)

      assert config.id == "json_job"
      assert config.starting_node_id == "node_0"
      assert config.nodes["node_0"].serving == :test_serving
      assert config.nodes["node_0"].agent_id == "json_agent"
    end
  end

  # ===========================================================================
  # Stop
  # ===========================================================================

  describe "stop" do
    @describetag :capture_log

    setup do
      original = Application.get_env(:agens, :backends)
      Application.put_env(:agens, :backends, [Agens.Backend.Log])
      on_exit(fn -> Application.put_env(:agens, :backends, original) end)
      :ok
    end

    setup :start_agens

    test "stop/1 terminates a job by run_id" do
      run_id = "stop_test_run_id"

      job = %Job.Config{
        id: "stop_job",
        starting_node_id: "node_0",
        nodes: %{"node_0" => %Job.Node{serving: :test_serving, agent_id: "first_agent"}}
      }

      {:ok, _pid} = Job.start(job, run_id)
      assert :ok == Job.stop(run_id)
    end

    test "stop/1 returns error when run not found" do
      assert {:error, :run_not_found} == Job.stop("nonexistent_stop_run_id")
    end
  end

  # ===========================================================================
  # Sub - job not loaded
  # ===========================================================================

  describe "sub - job not loaded" do
    setup do
      original = Application.get_env(:agens, :backends)
      Application.put_env(:agens, :backends, [Agens.Backend.Emit])
      on_exit(fn -> Application.put_env(:agens, :backends, original) end)
      :ok
    end

    setup [:start_agens, :start_serving]

    test "emits job_not_loaded error when no backend provides a sub spec" do
      id = "no_sub_loaded_job"
      run_id = "no_sub_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        nodes: %{
          "node_0" => %Job.Node{serving: :test_serving, sub: "nonexistent_sub_job"}
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", [])

      assert_receive {:job_run, ^id, ^run_id}
      assert_receive {:job_error, %Message{node_id: "node_0"}, :job_not_loaded}
    end
  end

  # ===========================================================================
  # Sub - error propagation
  # ===========================================================================

  describe "sub - error propagation" do
    setup do
      original = Application.get_env(:agens, :backends)
      Application.put_env(:agens, :backends, [Test.Support.ErrorSubBackend])
      on_exit(fn -> Application.put_env(:agens, :backends, original) end)
      :ok
    end

    setup [:start_agens, :start_serving]

    test "node sub error propagates to parent with parent node context" do
      input = "S"
      id = "sub_error_parent_job"
      run_id = "sub_error_parent_run_id"
      sub_id = "sub_error"
      sub_run_id = "sub_error_run_id"

      job = %Job.Config{
        id: id,
        starting_node_id: "node_0",
        description: "to test sub error propagation",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            sub: sub_id
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, [])

      assert_receive {:job_run, ^id, ^run_id}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        node_id: "node_0",
                        input: ^input
                      }}

      assert_receive {:job_run, ^sub_id, ^sub_run_id}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^sub_id,
                        run_id: ^sub_run_id,
                        parent_run_id: ^run_id,
                        node_id: "sub_node_0",
                        input: ^input
                      }}

      assert_receive {:job_error,
                      %Message{
                        job_id: ^sub_id,
                        run_id: ^sub_run_id,
                        node_id: "sub_node_0",
                        input: ^input
                      }, :sub_fatal_error}

      assert_receive {:job_error,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        node_id: "node_0",
                        input: ^input
                      }, :sub_fatal_error}
    end
  end

  # ===========================================================================
  # Config validation
  # ===========================================================================

  describe "Config.validate!/1" do
    test "raises ArgumentError when a Node is missing :serving" do
      config =
        Job.Config.from_map(%{
          "id" => "missing_serving_job",
          "starting_node_id" => "node_0",
          "nodes" => %{"node_0" => %{"agent_id" => "a", "objective" => "o"}}
        })

      assert_raise ArgumentError, ~r/"node_0" is missing required field :serving/, fn ->
        Job.Config.validate!(config)
      end
    end

    test "Job.start/2 invokes Config.validate!/1 and raises on invalid config" do
      {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})

      config =
        Job.Config.from_map(%{
          "id" => "start_validate_job",
          "starting_node_id" => "node_0",
          "nodes" => %{"node_0" => %{"agent_id" => "a"}}
        })

      assert_raise ArgumentError, ~r/"node_0" is missing required field :serving/, fn ->
        Job.start(config, "start_validate_run_id")
      end
    end
  end

  # ===========================================================================
  # State.Yield nil-clause guards
  # ===========================================================================

  describe "State.Yield" do
    test "thread_done/2 with nil yield returns an empty Yield struct" do
      result = Yield.thread_done(nil, "thread_1")
      assert %Yield{} = result
      assert result.threads == []
    end

    test "thread_add/2 with nil yield creates a new Yield with the thread" do
      result = Yield.thread_add(nil, "thread_1")
      assert "thread_1" in result.threads
    end

    test "thread_ready/3 with nil yield creates a new Yield with the ready entry" do
      result = Yield.thread_ready(nil, "thread_1", "node_10")
      assert {"thread_1", "node_10"} in result.ready
    end
  end
end
