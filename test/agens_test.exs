defmodule AgensTest do
  use ExUnit.Case
  doctest Agens

  alias Agens.{Agent, Job}

  defp serving() do
    auth_token = System.get_env("HF_AUTH_TOKEN")
    repo = {:hf, "mistralai/Mistral-7B-Instruct-v0.2", auth_token: auth_token}

    {:ok, model} = Bumblebee.load_model(repo, type: :bf16)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, generation_config} = Bumblebee.load_generation_config(repo)

    Bumblebee.Text.generation(model, tokenizer, generation_config)
  end

  setup_all do
    IO.puts("Enabling EXLA Backend")
    Application.put_env(:nx, :default_backend, EXLA.Backend)
    IO.puts("Starting Agens Supervisor")

    Supervisor.start_link(
      [
        {Agens, name: Agens}
      ],
      strategy: :one_for_one
    )

    IO.puts("Building Serving")

    text_generation = serving()

    IO.puts("Starting Agents")

    agents =
      [
        %Agent{
          name: :first_agent,
          serving: text_generation,
          context: """
          You are an agent for testing a multi-agent workflow. Your job is to take an input letter of the English alphabet, like 'J', and return only the letter that comes after the next letter in the alphabet.

          For example:
          Input: J
          Output: L

          Input: B
          Output: D

          You will always return a capital letter, regardless of input case. If you reach the end of the alphabet, just cycle back to the beginning i.e. 'A'.

          If anything except a single letter is provided, simply return 'ERROR'.
          """,
          knowledge: ""
        },
        %Agent{
          name: :second_agent,
          serving: text_generation,
          context: """
          You are an agent for testing a multi-agent workflow. Your job is to take an input letter of the English alphabet, like 'J', and return only the letter that comes before that letter in the alphabet.

          For example:
          Input: J
          Output: L

          Input: B
          Output: D

          You will always return a capital letter, regardless of input case. If you reach the beginning of the alphabet, just cycle back to the end i.e. 'Z'.

          If anything except a single letter is provided, simply return 'ERROR'.
          """,
          knowledge: ""
        },
        %Agent{
          name: :verifier_agent,
          serving: text_generation,
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

    @tag :skip
    test "stop agent" do
      result = Agens.stop_agent(:first_agent)
      assert result

      result = Agens.message(:first_agent, "B")
      assert result == {:error, :agent_not_running}
    end

    test "message running agent" do
      msg = "D"

      context =
        "<s>[INST]Which letter comes after '#{msg}' in the English alphabet? Return the letter only, no extra words, characters or tokens.[/INST]"

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
      } = Agens.message(:first_agent, context)

      assert text == "E"

      assert input == 34
      assert output == 2
    end

    test "message non-existent agent" do
      result = Agens.message(:missing_agent, "J")
      assert result == {:error, :agent_not_running}
    end

    test "stop non-existent agent" do
      result = Agens.stop_agent(:missing_agent)
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

      {:ok, pid} = Agens.start_job(job)
      assert is_pid(pid)
      assert job == Job.get_config(pid)
      assert job == Job.get_config(:first_job)
      assert {:error, :job_not_found} == Job.get_config(:missing_job)
    end
  end
end
