defmodule Agens.Backend.EmitTest do
  use ExUnit.Case, async: true

  alias Agens.{Backend.Emit, Message, Resource}

  defp message(overrides \\ []) do
    struct(
      %Message{
        input: "test",
        caller: self(),
        run_id: "run_1",
        node_id: "node_1",
        thread_id: "thread_1"
      },
      overrides
    )
  end

  test "run/3 sends {:job_run, job_id, run_id} to caller" do
    assert :ok == Emit.run(self(), "job_1", "run_1")
    assert_received {:job_run, "job_1", "run_1"}
  end

  test "status/3 sends {:job_status, {run_id, status}} to caller" do
    assert :ok == Emit.status(self(), "run_1", :running)
    assert_received {:job_status, {"run_1", :running}}
  end

  test "complete/2 sends {:job_complete, run_id} to caller" do
    assert :ok == Emit.complete(self(), "run_1")
    assert_received {:job_complete, "run_1"}
  end

  test "ended/2 sends {:job_ended, run_id} to caller" do
    assert :ok == Emit.ended(self(), "run_1")
    assert_received {:job_ended, "run_1"}
  end

  test "error/3 sends {:job_error, message, error} to caller" do
    msg = message()
    assert :ok == Emit.error(self(), msg, :some_error)
    assert_received {:job_error, ^msg, :some_error}
  end

  test "node_started/2 sends {:node_started, message} to caller" do
    msg = message()
    assert :ok == Emit.node_started(self(), msg)
    assert_received {:node_started, ^msg}
  end

  test "node_retry/2 sends {:node_retry, message} to caller" do
    msg = message()
    assert :ok == Emit.node_retry(self(), msg)
    assert_received {:node_retry, ^msg}
  end

  test "node_result/2 sends {:node_result, message} to caller" do
    msg = message()
    assert :ok == Emit.node_result(self(), msg)
    assert_received {:node_result, ^msg}
  end

  test "tool_call/3 sends {:tool_call, message, tool_call} to caller" do
    msg = message()
    tc = %{name: "my_tool", arguments: %{"foo" => "bar"}, result: "ok", error: nil}
    assert :ok == Emit.tool_call(self(), msg, tc)
    assert_received {:tool_call, ^msg, ^tc}
  end

  test "resource_load/3 sends {:resource_load, message, resource} to caller" do
    msg = message()
    resource = %Resource{uri: "file://test", name: "test", description: "test"}
    assert :ok == Emit.resource_load(self(), msg, resource)
    assert_received {:resource_load, ^msg, ^resource}
  end

  test "prompt/1 sends {:prompt, {system, user}} to message.caller" do
    msg = message(system: "sys_prompt", user: "user_prompt")
    assert :ok == Emit.prompt(msg)
    assert_received {:prompt, {"sys_prompt", "user_prompt"}}
  end

  test "yield_wait/4 sends {:yield_wait, {message, total_count, ready_count}} to caller" do
    msg = message()
    Emit.yield_wait(self(), msg, 5, 3)
    assert_received {:yield_wait, {^msg, 5, 3}}
  end

  test "yield_done/3 sends {:yield_done, {message, total_count}} to caller" do
    msg = message()
    Emit.yield_done(self(), msg, 5)
    assert_received {:yield_done, {^msg, 5}}
  end

  test "sub/2 returns nil" do
    assert nil == Emit.sub(self(), "job_1")
  end
end
