defmodule Agens.ServingTest do
  use Test.Support.AgentCase, async: false

  import ExUnit.CaptureLog

  alias Agens.{Message, Serving}

  defp start_agens(_ctx) do
    {:ok, _pid} = start_supervised({Agens.Supervisor, name: Agens.Supervisor})
    :ok
  end

  defp start_serving(_ctx) do
    config = %Serving.Config{
      name: :serving_test,
      serving: Test.Support.Serving.Stub
    }

    {:ok, pid} = Serving.start(config)

    [
      config: config,
      pid: pid
    ]
  end

  describe "serving" do
    setup [:start_agens, :start_serving]

    test "message", %{config: config} do
      input = "input"

      message =
        %Message{serving_name: config.name, input: input}
        |> Serving.run()

      assert message == "sent '#{input}' to: "
    end

    test "start running", %{config: config, pid: pid} do
      assert is_pid(pid)

      assert capture_log([level: :warning], fn ->
               Serving.start(config)
             end) =~ "Serving #{config.name} already started"
    end
  end

  describe "stop" do
    setup [:start_agens, :start_serving]

    test "stop", %{config: config} do
      assert :ok == Serving.stop(config.name)
    end

    test "stop missing" do
      assert {:error, :serving_not_found} ==
               Serving.stop(:serving_missing)
    end
  end
end
