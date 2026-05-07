defmodule Agens.Backend.LogTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Agens.{Backend.Log, Message}

  defp message(overrides \\ []) do
    struct(
      %Message{
        input: "test",
        run_id: "run_1",
        node_id: "node_1",
        thread_id: "thread_1"
      },
      overrides
    )
  end

  test "start/3 logs job info and returns :ok" do
    log = capture_log(fn -> assert :ok == Log.start(nil, "job_1", "run_1") end)
    assert log =~ "Starting job"
    assert log =~ "job_1"
    assert log =~ "run_1"
  end

  test "status/3 logs run status and returns :ok" do
    log = capture_log(fn -> assert :ok == Log.status(nil, "run_1", :running) end)
    assert log =~ "run_1"
    assert log =~ "status change"
  end

  test "complete/2 logs completion and returns :ok" do
    log = capture_log(fn -> assert :ok == Log.complete(nil, "run_1") end)
    assert log =~ "run_1"
    assert log =~ "complete"
  end

  test "error/3 logs error details and returns :ok" do
    msg = message()
    log = capture_log(fn -> assert :ok == Log.error(nil, msg, :some_error) end)
    assert log =~ "Error"
    assert log =~ "run_1"
    assert log =~ "node_1"
  end

  test "node_started/2 logs node start info and returns :ok" do
    msg = message()
    log = capture_log(fn -> assert :ok == Log.node_started(nil, msg) end)
    assert log =~ "Starting node"
    assert log =~ "node_1"
    assert log =~ "run_1"
  end

  test "node_retry/2 logs retry info and returns :ok" do
    msg = message()
    log = capture_log(fn -> assert :ok == Log.node_retry(nil, msg) end)
    assert log =~ "Retrying node"
    assert log =~ "node_1"
  end

  test "node_result/2 logs completion info and returns :ok" do
    msg = message()
    log = capture_log(fn -> assert :ok == Log.node_result(nil, msg) end)
    assert log =~ "Completed node"
    assert log =~ "node_1"
  end

  test "tool_call/4 logs tool invocation and returns :ok" do
    log = capture_log(fn -> assert :ok == Log.tool_call(nil, "job_1", "run_1", "my_tool") end)
    assert log =~ "Tool call"
    assert log =~ "my_tool"
    assert log =~ "job_1"
  end

  test "prompt/1 returns :ok without logging" do
    msg = message()
    log = capture_log(fn -> assert :ok == Log.prompt(msg) end)
    assert log == ""
  end

  test "yield_wait/4 logs ready/total counts and returns :ok" do
    msg = message()
    log = capture_log(fn -> assert :ok == Log.yield_wait(nil, msg, 5, 3) end)
    assert log =~ "Yield wait"
    assert log =~ "3/5"
  end

  test "yield_done/3 logs total count and returns :ok" do
    msg = message()
    log = capture_log(fn -> assert :ok == Log.yield_done(nil, msg, 5) end)
    assert log =~ "Yield done"
    assert log =~ "5"
  end

  test "sub/2 returns nil" do
    assert nil == Log.sub(nil, "job_1")
  end
end
