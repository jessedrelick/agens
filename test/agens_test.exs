defmodule Agens.AgensTest do
  use ExUnit.Case, async: false
  # doctest Agens

  describe "backends/0" do
    test "returns a list of backend modules from application config" do
      backends = Agens.backends()
      assert is_list(backends)
      assert length(backends) > 0
      assert Enum.all?(backends, &is_atom/1)
    end
  end

  describe "backends/2" do
    test "applies the given function to all configured backends and returns results" do
      results = Agens.backends(:sub, ["some_job"])
      assert is_list(results)
      assert length(results) == length(Agens.backends())
    end
  end

  describe "job_pid/3" do
    setup do
      {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})
      :ok
    end

    test "finds a registered job process by run_id" do
      run_id = "job_pid_test_run_id"

      job = %Agens.Job.Config{
        id: "job_pid_job",
        starting_node_id: "node_0",
        nodes: %{}
      }

      {:ok, pid} = Agens.Job.start(job, run_id)
      result = Agens.job_pid(run_id, {:error, :not_found}, fn p -> p end)
      assert result == pid
    end

    test "returns the error value when run_id is not registered" do
      result = Agens.job_pid("unknown_run_id", {:error, :not_found}, fn _ -> :found end)
      assert result == {:error, :not_found}
    end
  end
end
