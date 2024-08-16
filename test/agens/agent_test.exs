defmodule Agens.AgentTest do
  use Test.Support.AgentCase, async: true

  alias Agens.{Agent, Job, Message}
  alias Test.Support.Tools.NoopTool

  describe "agents" do
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

      :meck.expect(Agent, :message, fn
        ^message -> :meck.passthrough([message])
      end)

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

    test "stop non-existent agent" do
      result = Agent.stop(:missing_agent)
      assert result == {:error, :agent_not_found}
    end
  end

  describe "messages" do
    @tag timeout: :infinity
    test "message sequence without job" do
      get_agent_configs()
      |> Agent.start()

      input = "D"

      :meck.expect(Agent, :message, fn %Message{agent_name: agent_name, input: input} = message ->
        result = map_input(agent_name, input)
        Map.put(message, :result, result)
      end)

      # 0
      message = %Message{agent_name: :first_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "C"
      message = %Message{agent_name: :second_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "E"
      message = %Message{agent_name: :verifier_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "E"

      # 1
      message = %Message{agent_name: :first_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "D"
      message = %Message{agent_name: :second_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "F"
      message = %Message{agent_name: :verifier_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "F"

      # 2
      message = %Message{agent_name: :first_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "E"
      message = %Message{agent_name: :second_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "G"
      message = %Message{agent_name: :verifier_agent, input: input}
      %Message{result: result} = Agent.message(message)
      input = post_process(result)
      assert input == "TRUE"
    end

    test "invalid message returns error" do
      agent_name = :second_agent
      input = "Here is some invalid input"

      :meck.expect(Agent, :message, fn %Message{agent_name: ^agent_name, input: ^input} = message ->
        result = map_input(agent_name, input)
        Map.put(message, :result, result)
      end)

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

      :meck.expect(Agent, :message, fn
        ^message -> :meck.passthrough([message])
      end)

      result = Agent.message(message)
      assert result == {:error, :agent_not_running}
    end
  end

  describe "prompt" do
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
end
