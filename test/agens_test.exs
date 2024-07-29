defmodule AgensTest do
  use ExUnit.Case
  doctest Agens

  alias Agens.{Agent, Archetypes, Job, Manager}

  setup_all do
    IO.puts("Enabling EXLA Backend")
    Application.put_env(:nx, :default_backend, EXLA.Backend)
    IO.puts("Starting Manager Supervisor")

    Supervisor.start_link(
      [
        {Manager, name: Manager}
      ],
      strategy: :one_for_one
    )

    IO.puts("Starting Agents")

    agents =
      [
        %Agent{
          name: Agens.FirstAgent,
          archetype: Archetypes.text_generation(),
          context: "",
          knowledge: ""
        },
        %Agent{
          name: :another_agent,
          archetype: Archetypes.text_generation(),
          context: "",
          knowledge: ""
        },
        %Agent{
          name: :verifier_agent,
          archetype: Archetypes.text_generation(),
          context: "",
          knowledge: ""
        }
      ]
      |> Agens.start()

    [
      agents: agents
    ]
  end

  describe "job" do
    test "start agents", %{agents: agents} do
      assert length(agents) == 3
      [{:ok, pid} | _] = agents
      assert is_pid(pid)
    end

    test "stop agent" do
      result = Manager.stop_worker(:another_agent)
      assert result

      result = Agens.message(:another_agent, "hello my name is")
      assert result == {:error, :agent_not_running}
    end

    test "message running agent" do
      %{
        results: [
          %{
            text: text,
            token_summary: %{
              input: input,
              output: output,
              padding: 0
            }
          }
        ]
      } = Agens.message(Agens.FirstAgent, "hello my name is")

      assert text ==
               " John. I'm a student at the University of California, Berkeley. I'm a student at the"

      assert input == 4
      assert output == 20
    end

    test "message non-existent agent" do
      result = Agens.message(:missing_agent, "hello my name is")
      assert result == {:error, :agent_not_running}
    end

    test "stop non-existent agent" do
      result = Manager.stop_worker(:missing_agent)
      assert result == {:error, :agent_not_found}
    end

    test "start job" do
      job = %Job.Config{
        name: :first_job,
        objective: "to create a sequence of steps",
        steps: [
          %Job.Step{
            agent: Agens.FirstAgent,
            prompt: "",
            conditions: ""
          },
          %Job.Step{
            agent: :another_agent,
            prompt: "",
            conditions: ""
          },
          %Job.Step{
            agent: :verifier,
            prompt: "",
            conditions: ""
          }
        ]
      }

      {:ok, pid} = Manager.start_job(job)
      assert is_pid(pid)
    end
  end
end
