defmodule Agens.AgentTest do
  use Test.Support.AgentCase, async: true

  alias Agens.{Agent, Job, Message}
  alias Test.Support.Tools.NoopTool

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

  describe "agents" do
    setup [:start_agens, :start_serving]

    test "start agents" do
      agents =
        [
          %Agent.Config{
            name: :test_start_agent,
            serving: :text_generation
          }
        ]
        |> Agent.start()

      assert length(agents) == 1
      [{:ok, pid}] = agents
      assert is_pid(pid)
    end

    test "stop agent" do
      agent_name = :test_stop_agent
      input = "test stop"

      message = %Message{
        agent_name: agent_name,
        input: input
      }

      agents =
        [
          %Agent.Config{
            name: agent_name,
            serving: :text_generation
          }
        ]
        |> Agent.start()

      assert length(agents) == 1
      [{:ok, pid}] = agents
      assert is_pid(pid)

      assert Agent.stop(:test_stop_agent) == :ok

      result = Agent.message(message)
      assert result == {:error, :agent_not_running}
    end
  end

  describe "errors" do
    setup [:start_agens, :start_serving]

    test "stop non-existent agent" do
      result = Agent.stop(:missing_agent)
      assert result == {:error, :agent_not_found}
    end

    test "invalid message returns error" do
      agent_name = :second_agent
      input = "Here is some invalid input"

      [
        %Agent.Config{
          name: agent_name,
          serving: :text_generation
        }
      ]
      |> Agent.start()

      message = %Message{
        agent_name: agent_name,
        input: input
      }

      message = Agent.message(message)

      assert message.result == "ERROR"
    end

    test "message non-existent agent" do
      message = %Message{
        agent_name: :missing_agent,
        input: "J"
      }

      result = Agent.message(message)
      assert result == {:error, :agent_not_running}
    end
  end

  # describe "sequence" do
  #   @tag timeout: :infinity
  #   test "message sequence without job" do
  #     get_agent_configs()
  #     |> Agent.start()

  #     input = "D"

  #     # 0
  #     message = %Message{agent_name: :first_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "C"
  #     message = %Message{agent_name: :second_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "E"
  #     message = %Message{agent_name: :verifier_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "E"

  #     # 1
  #     message = %Message{agent_name: :first_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "D"
  #     message = %Message{agent_name: :second_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "F"
  #     message = %Message{agent_name: :verifier_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "F"

  #     # 2
  #     message = %Message{agent_name: :first_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "E"
  #     message = %Message{agent_name: :second_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "G"
  #     message = %Message{agent_name: :verifier_agent, input: input}
  #     %Message{result: result} = Agent.message(message)
  #     input = post_process(result)
  #     assert input == "TRUE"
  #   end
  # end
end
