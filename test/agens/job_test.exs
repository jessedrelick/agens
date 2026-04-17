defmodule Agens.JobTest do
  use ExUnit.Case, async: false

  alias Agens.{Job, Message, Prefixes, Resource}
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

    :ok
  end

  defp start_job(_ctx) do
    job = %Job.Config{
      id: "first_job",
      description: "to create a sequence of nodes",
      nodes: %{
        "node_0" => %Job.Node{
          serving: :test_serving,
          agent_id: :first_agent,
          objective: "test node objective"
        },
        "node_10" => %Job.Node{
          serving: :test_serving,
          agent_id: :second_agent
        },
        "node_20" => %Job.Node{
          serving: :test_serving,
          agent_id: :verifier_agent
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
      assert {:error, :run_not_found} == Job.run("nonexistent_run_id", "input", "node_0", [])
    end

    test "job already running", %{run_id: run_id} do
      input = "input"
      node_id = "node_0"

      :ok = Job.run(run_id, input, node_id, [])
      assert {:error, :job_already_running} == Job.run(run_id, input, node_id, [])
    end

    test "nil input", %{run_id: run_id} do
      assert {:error, :input_required} == Job.run(run_id, nil, "node_0", [])
    end

    test "invalid node id", %{job: %{id: id, description: description}, run_id: run_id} do
      input = "input"
      node_id = "invalid_node_id"
      caller = self()

      :ok = Job.run(run_id, input, node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

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
      first_node_id = "node_0"
      caller = self()
      next = "invalid next node"

      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
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
                        node_id: ^first_node_id,
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
        nodes: []
      }

      {:ok, pid} = Job.start(job, "job_config_run_id")

      assert is_pid(pid)
      assert {:ok, job} == Job.get_config(pid)
      assert {:error, :job_not_found} == Job.get_config("missing_job")
    end

    @tag :skip
    test "config - by run id" do
      run_id = "run_id_123abc"

      job = %Job.Config{
        id: "job_config",
        nodes: []
      }

      {:ok, pid} = Job.start(job, run_id)

      assert is_pid(pid)
      assert {:ok, job} == Job.get_config(pid)
      assert {:ok, job} == Job.get_config(run_id)
      assert {:error, :job_not_found} == Job.get_config(job.id)
    end
  end

  describe "sequence" do
    setup [:start_agens, :start_serving, :start_job]

    @tag :skip
    test "start", %{job: %{id: id} = job, pid: pid} do
      input = "D"
      first_node_id = "node_0"
      run_id = "test_run_id"

      assert is_pid(pid)
      {:error, {:already_started, ^pid}} = Job.start(job, run_id)
      :ok = Job.run(id, input, first_node_id, [])

      assert_receive {:job_started, ^id, nil}

      # FIRST ITERATION
      # Agent 1
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: ^input,
                        result: "C",
                        next: [{:route, "node_10", 1}]
                      }}

      # Agent 2
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :second_agent,
                        node_id: "node_10",
                        input: "C"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :second_agent,
                        node_id: "node_10",
                        input: "C",
                        result: "E",
                        next: [{"node_20", 1}]
                      }}

      # Agent 3
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: "E"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: "E",
                        result: "E",
                        next: [{:route, "node_0", 1}]
                      }}

      # SECOND ITERATION
      # Agent 1
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: "E"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: "E",
                        result: "D",
                        next: [{:route, "node_10", 1}]
                      }}

      # Agent 2
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :second_agent,
                        node_id: "node_10",
                        input: "D"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :second_agent,
                        node_id: "node_10",
                        input: "D",
                        result: "F",
                        next: [{:route, "node_20", 1}]
                      }}

      # Agent 3
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: "F"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: "F",
                        result: "F",
                        next: [{:route, "node_0", 1}]
                      }}

      # FINAL ITERATION
      # Agent 1
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: "F"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: "F",
                        result: "E",
                        next: [{:route, "node_10", 1}]
                      }}

      # Agent 2
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :second_agent,
                        node_id: "node_10",
                        input: "E"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :second_agent,
                        node_id: "node_10",
                        input: "E",
                        result: "G",
                        next: [{:route, "node_20", 1}]
                      }}

      # Agent 3
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: "G"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: "G",
                        result: "TRUE",
                        next: [:end]
                      }}

      # END
      assert_receive {:job_complete, nil}

      # TODO: pid should be removed from registry automatically after being stopped
      completed_pid = Agens.job_pid(id, {:error, :job_not_found}, fn pid -> pid end)
      assert is_pid(completed_pid)
      assert completed_pid == pid
      # Job.run(name, nil, nil, nil)
      {:ok, new_pid} = Job.start(job, "new_run_id")
      assert is_pid(new_pid)
      assert new_pid != pid
    end

    test "start with run id", %{job: %{id: id} = job} do
      input = "F"
      first_node_id = "node_0"
      run_id = "test_run_id"

      {:ok, pid} = Job.start(job, run_id)

      assert is_pid(pid)
      {:error, {:already_started, ^pid}} = Job.start(job, run_id)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

      # Agent 1
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :first_agent,
                        node_id: ^first_node_id,
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
                        agent_id: :second_agent,
                        node_id: "node_10",
                        input: ^input,
                        previous_result: "E"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :second_agent,
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
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: ^input,
                        previous_result: "G"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :verifier_agent,
                        node_id: "node_20",
                        input: ^input,
                        result: "TRUE",
                        previous_result: "G",
                        next: [:end]
                      }}

      # END
      assert_receive {:job_status, {^run_id, :running}}
      assert_receive {:job_complete, ^run_id}
    end
  end

  describe "parallel" do
    setup [:start_agens, :start_serving]

    test "multiple threads" do
      input = "H"
      first_node_id = "node_0"
      id = "parallel_job"
      run_id = "test_parallel_run_id"

      job = %Job.Config{
        id: id,
        description: "to execute multiple agents in parallel",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :parallel_agent,
            objective: "test fan out"
          },
          "node_10" => %Job.Node{
            serving: :test_serving,
            agent_id: :default_agent,
            objective: "test parallel execution"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

      # Fan out
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :parallel_agent,
                        node_id: ^first_node_id,
                        input: "H"
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :parallel_agent,
                        node_id: ^first_node_id,
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
                        agent_id: :default_agent,
                        node_id: "node_10",
                        input: "H",
                        thread_id: thread_id_1
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :default_agent,
                        node_id: "node_10",
                        input: "H",
                        thread_id: thread_id_2
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :default_agent,
                        node_id: "node_10",
                        input: "H",
                        thread_id: thread_id_3
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :default_agent,
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
                        agent_id: :default_agent,
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
                        agent_id: :default_agent,
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
                        agent_id: :default_agent,
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
                        agent_id: :default_agent,
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
      first_node_id = "node_0"
      id = "retries_job"
      run_id = "test_retries_run_id"
      agent_id = :retry_agent
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
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
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        retries: 0,
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: ^agent_id,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}

      refute user =~ retry_prefix

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: ^first_node_id,
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
                        node_id: ^first_node_id,
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
                        node_id: ^first_node_id,
                        input: ^input,
                        result: nil,
                        next: []
                      }}

      assert_receive {:job_error,
                      %Message{
                        retries: 3,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: ^first_node_id,
                        input: ^input,
                        result: nil,
                        next: []
                      }, :max_retries}
    end

    test "explict retry" do
      input = "explicit"
      first_node_id = "node_0"
      id = "retries_job"
      run_id = "test_explicit_retry_run_id"
      result = "explicit retry"
      agent_id = :retry_agent
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
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
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        retries: 0,
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: ^agent_id,
                        node_id: ^first_node_id,
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
                        node_id: ^first_node_id,
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
      #                   node_id: ^first_node_id,
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
      #                   node_id: ^first_node_id,
      #                   input: ^input,
      #                   result: nil,
      #                   next: nil
      #                 }}

      # assert_receive {:job_error,
      #                 %Message{
      #                   retries: 3,
      #                   job_id: ^name,
      #                   agent_id: ^agent_id,
      #                   node_id: ^first_node_id,
      #                   input: ^input,
      #                   result: nil,
      #                   next: nil
      #                 }, :max_retries}
    end

    test "config max retries" do
      input = "error"
      first_node_id = "node_0"
      id = "retries_job"
      run_id = "test_retries_config_run_id"
      agent_id = :retry_agent
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
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
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started,
                      %Message{
                        retries: 0,
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: ^agent_id,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}

      refute user =~ retry_prefix

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        job_id: ^id,
                        agent_id: ^agent_id,
                        node_id: ^first_node_id,
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
                        node_id: ^first_node_id,
                        input: ^input,
                        result: nil,
                        next: []
                      }, :max_retries}
    end

    test "retry with reason from serving" do
      input = "error"
      first_node_id = "node_0"
      id = "retries_job"
      run_id = "test_retry_reason_run_id"
      agent_id = :retry_agent
      retry_reason = "validation error"
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
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
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

      assert_receive {:node_started, %Message{retries: 0}}

      assert_receive {:prompt, {_system, user}}
      refute user =~ retry_prefix

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        retry_reason: ^retry_reason,
                        job_id: ^id,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}
      assert user =~ retry_prefix
      assert user =~ retry_reason

      assert_receive {:job_error, %Message{retries: 1}, :max_retries}
    end

    test "retry with reason from next" do
      input = "explicit_with_reason"
      first_node_id = "node_0"
      id = "retries_job"
      run_id = "test_retry_reason_next_run_id"
      agent_id = :retry_agent
      retry_reason = "LLM provided reason"
      {_, retry_prefix} = Prefixes.default() |> Map.get(:retry)

      job = %Job.Config{
        id: id,
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
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

      assert_receive {:node_started, %Message{retries: 0}}

      assert_receive {:prompt, {_system, user}}
      refute user =~ retry_prefix

      assert_receive {:node_result, %Message{}}

      assert_receive {:node_retry,
                      %Message{
                        retries: 1,
                        retry_reason: ^retry_reason,
                        job_id: ^id,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, {_system, user}}
      assert user =~ retry_prefix
      assert user =~ retry_reason

      assert_receive {:job_error, %Message{retries: 1}, :max_retries}
    end

    test "error terminates immediately" do
      input = "fatal"
      first_node_id = "node_0"
      id = "retries_job"
      run_id = "test_error_terminates_run_id"
      agent_id = :retry_agent

      job = %Job.Config{
        id: id,
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
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

      assert_receive {:node_started, %Message{retries: 0}}

      assert_receive {:job_error, %Message{retries: 0, node_id: ^first_node_id}, :fatal_error}

      refute_receive {:node_retry, %Message{}}
    end
  end

  describe "end" do
    setup [:start_agens, :start_serving]

    test "ends job immediately" do
      input = "input"
      first_node_id = "node_0"
      id = "end_job"
      run_id = "test_end_run_id"

      job = %Job.Config{
        id: id,
        description: "to end job",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :end_agent,
            objective: "test end node"
          },
          "node_10" => %Job.Node{
            serving: :test_serving,
            agent_id: :first_agent,
            objective: "noop"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, _prompt}
      assert_receive {:node_result, %Message{next: [:end]}}

      assert_receive {:job_complete, ^run_id}
    end
  end

  describe "restart" do
    setup [:start_agens, :start_serving]

    test "crash" do
      input = "unhandled exception"
      id = "crash_job"
      first_node_id = "node_0"
      run_id = "crash_run_id"

      job = %Job.Config{
        id: id,
        description: "to simulate a crash",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :error_agent
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
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
      # assert_receive {:job_started, ^name}
    end
  end

  describe "tools" do
    setup [:start_agens, :start_serving, :start_job]

    test "tool" do
      input = "T"
      id = "test_tool_job"
      first_node_id = "node_0"
      run_id = "test_tool_run_id"
      tool_name = "test_tool_name"
      tool_call_id = "tool_call_id"

      job = %Job.Config{
        id: id,
        description: "to test tool usage",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :tool_agent,
            objective: "agent for testing tools",
            tools: [
              Tools.tool_def()
            ]
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)

      assert is_pid(pid)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, _prompt}
      assert_receive {:tool_call, {^id, ^run_id, ^tool_name}}
      assert_receive {:node_result, %Message{tool_results: tool_results}}
      result = Map.get(tool_results, tool_call_id)

      assert result == "tool result for: #{tool_call_id}"

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, _prompt}
      # assert_receive {:node_result, %Message{}}
      # assert_receive {:job_complete, ^run_id}
    end
  end

  describe "resources" do
    setup [:start_agens, :start_serving]

    test "resource content is loaded and appears in system prompt" do
      id = "test_resource_job"
      run_id = "test_resource_run_id"
      first_node_id = "node_0"
      resource = Resources.resource_def()

      job = %Job.Config{
        id: id,
        description: "to test resource loading",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :resource_agent,
            objective: "agent for testing resources",
            resources: [resource]
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
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
      first_node_id = "node_0"
      resource = Resources.resource_def(:no_content)

      job = %Job.Config{
        id: id,
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :resource_agent,
            resources: [resource]
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", first_node_id, [])

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, {system, _user}}

      refute system =~ "### #{resource.uri}"
      refute system =~ "## Resources"
    end

    test "multiple resources load in parallel and all appear in prompt" do
      id = "test_multi_resource_job"
      run_id = "test_multi_resource_run_id"
      first_node_id = "node_0"
      resource = Resources.resource_def()

      job = %Job.Config{
        id: id,
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :resource_agent,
            resources: [resource, resource]
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", first_node_id, [])

      assert_receive {:node_started, %Message{}}
      assert_receive {:prompt, {system, _user}}

      expected_content = Resources.resource_content(resource.uri)
      assert String.count(system, expected_content) == 2
    end

    test "node without resources sends prompt with no resource section" do
      id = "test_no_resource_job"
      run_id = "test_no_resource_run_id"
      first_node_id = "node_0"

      job = %Job.Config{
        id: id,
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :resource_agent
          }
        }
      }

      {:ok, _pid} = Job.start(job, run_id)
      :ok = Job.run(run_id, "input", first_node_id, [])

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
      agent_id = :test_prompt_agent
      input = "test input"
      first_node_id = "node_0"
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

      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^job_id, ^run_id}

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
      first_node_id = "node_0"
      id = "yield_job"
      run_id = "test_yield_run_id"

      job = %Job.Config{
        id: id,
        description: "to yield and aggregate results",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :split_agent,
            objective: "test split node objective"
          },
          "node_10" => %Job.Node{
            serving: :test_serving,
            agent_id: :concurrent_agent,
            objective: "test concurrent node objective"
          },
          "node_20" => %Job.Node{
            serving: :test_serving,
            agent_id: :yield_agent,
            objective: "test yield node objective"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}

      # Fan out
      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :split_agent,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}
      assert_receive {:job_status, {^run_id, :running}}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :split_agent,
                        node_id: ^first_node_id,
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
                        agent_id: :concurrent_agent,
                        node_id: "node_10",
                        input: ^input,
                        thread_id: thread_id_1
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :concurrent_agent,
                        node_id: "node_10",
                        input: ^input,
                        thread_id: thread_id_2
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :concurrent_agent,
                        node_id: "node_10",
                        input: ^input,
                        thread_id: thread_id_3
                      }}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :concurrent_agent,
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
                        agent_id: :concurrent_agent,
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
                        agent_id: :concurrent_agent,
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
                        agent_id: :concurrent_agent,
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
                        agent_id: :concurrent_agent,
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
                        agent_id: :yield_agent,
                        node_id: "node_20",
                        input: ^input
                      }}

      assert_receive {:prompt, _prompt}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :yield_agent,
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
      first_node_id = "node_0"
      id = "sub_job"
      run_id = "test_sub_run_id"
      sub_id = "sub"
      sub_run_id = "sub_run_id"
      sub_first_node_id = "sub_node_0"
      sub_final_agent = :sub_final_agent
      sub_result = "sent '#{input}' to: #{sub_final_agent}"

      job = %Job.Config{
        id: id,
        description: "to spawn a sub job via route instruction",
        nodes: %{
          "node_0" => %Job.Node{
            serving: :test_serving,
            agent_id: :sub_agent,
            objective: "test sub job"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}
      assert_receive {:prompt, _prompt}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        agent_id: :sub_agent,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      assert_receive {:node_result,
                      %Message{
                        job_id: ^id,
                        agent_id: :sub_agent,
                        node_id: ^first_node_id,
                        input: ^input,
                        result: ^input,
                        next: [{:sub, "sub_job"}]
                      }}

      # Sub Job
      assert_receive {:job_started, ^sub_id, ^sub_run_id}
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
    end

    test "node sub" do
      input = "S"
      first_node_id = "node_0"
      id = "sub_job"
      run_id = "test_sub_run_id"
      sub_id = "sub"
      sub_run_id = "sub_run_id"
      sub_first_node_id = "sub_node_0"
      sub_final_agent = :sub_final_agent
      sub_result = "sent '#{input}' to: #{sub_final_agent}"

      job = %Job.Config{
        id: id,
        description: "to spawn a sub job via node sub field",
        nodes: %{
          "node_0" => %Job.Node{
            sub: sub_id,
            objective: "test sub job"
          }
        }
      }

      {:ok, pid} = Job.start(job, run_id)
      assert is_pid(pid)
      :ok = Job.run(run_id, input, first_node_id, [])

      assert_receive {:job_started, ^id, ^run_id}
      assert_receive {:job_status, {^run_id, :running}}
      assert_receive {:prompt, _prompt}

      assert_receive {:node_started,
                      %Message{
                        job_id: ^id,
                        run_id: ^run_id,
                        node_id: ^first_node_id,
                        input: ^input
                      }}

      # Sub Job
      assert_receive {:job_started, ^sub_id, ^sub_run_id}
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
      # assert_receive {:node_result,
      #                 %Message{
      #                   job_id: ^name,
      #                   agent_id: nil,
      #                   node_id: ^first_node_id,
      #                   input: ^input,
      #                   result: ^sub_result,
      #                   next: []
      #                 }}

      # assert_receive {:job_complete, ^run_id}
    end
  end
end
