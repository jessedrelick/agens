defmodule AgensTest do
  use ExUnit.Case, async: true
  doctest Agens

  alias Agens.{Agent, Job}

  @real_llm false

  defmodule TestServing do
    use GenServer

    def run(prompt) do
      GenServer.call(__MODULE__, {:run, prompt})
    end

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, opts)
    end

    def init(opts) do
      {:ok, opts}
    end

    def handle_call({:run, _prompt, input}, _, state) do
      agent = Keyword.get(state, :config)
      text = map_input(agent.name, input)
      output = %{results: [%{text: text}]}
      {:reply, output, state}
    end

    defp map_input(:first_agent, input) do
      %{
        "D" => "C",
        "E" => "D",
        "F" => "E"
      }
      |> Map.get(input, "ERROR")
    end

    defp map_input(:second_agent, input) do
      %{
        "C" => "E",
        "D" => "F",
        "E" => "G"
      }
      |> Map.get(input, "ERROR")
    end

    defp map_input(:verifier_agent, input) do
      if input == "G", do: "TRUE", else: "FALSE"
    end
  end

  defp serving(true) do
    auth_token = System.get_env("HF_AUTH_TOKEN")
    repo = {:hf, "mistralai/Mistral-7B-Instruct-v0.2", auth_token: auth_token}

    {:ok, model} = Bumblebee.load_model(repo, type: :bf16)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, generation_config} = Bumblebee.load_generation_config(repo)

    Bumblebee.Text.generation(model, tokenizer, generation_config)
  end

  defp serving(_) do
    TestServing
  end

  defp post_process(text) do
    cond do
      String.contains?(text, "Based on the given input") ->
        text
        |> String.split("`")
        |> Enum.at(3)

      String.contains?(text, "Here's a brief explanation of the logic behind the code:") ->
        String.first(text)

      String.contains?(text, "Here's a Python solution") ->
        String.first(text)

      String.contains?(text, "TRUE") ->
        "TRUE"

      String.contains?(text, "FALSE") ->
        "FALSE"

      true ->
        if @real_llm do
          IO.inspect(text, label: "NO POST PROCESS MATCH")
        end

        text
    end
  end

  setup_all do
    IO.puts("Enabling EXLA Backend")
    Application.put_env(:nx, :default_backend, EXLA.Backend)
    IO.puts("Starting Agens Supervisor")

    Supervisor.start_link(
      [
        {Agens, name: Agens},
        {Registry, keys: :unique, name: Agens.Registry.Agents}
      ],
      strategy: :one_for_one
    )

    IO.puts("Building Serving")

    text_generation = serving(@real_llm)

    IO.puts("Starting Agents")

    agents =
      [
        %Agent{
          name: :first_agent,
          serving: text_generation,
          prompt:
            "Return the capital letter one place before the letter in the English alphabet provided after 'Input: '. If you reach the start of the alphabet, cycle to the end of the alphabet i.e. 'Z'. For invalid input, which would be anything other than a single letter after 'Input: ' simply return 'ERROR'. The output response should only be the letter without any additional characters, tokens, or whitespace, or ERROR in case of invalid input.",
          knowledge: ""
        },
        %Agent{
          name: :second_agent,
          serving: text_generation,
          prompt: %Agent.Prompt{
            identity:
              "You are an AI agent that takes an input letter of the English alphabet and returns the capital letter two places ahead of the letter. If the input is anything but a single letter, your return 'ERROR'",
            context: "You are used as part of a unit test suite for a multi-agent workflow",
            constraints:
              "Your output should only be a single capital letter from the English alphabet, or 'ERROR'",
            examples: [
              %{input: "A", output: "C"},
              %{input: "F", output: "H"},
              %{input: "9vasg2rwe", output: "ERROR"}
            ],
            reflection:
              "Before returning a result please ensure it is either a capital letter of the English alphabet or 'ERROR'"
          },
          # "<s>[INST]Which letter comes after '#{msg}' in the English alphabet? Return the letter only, no extra words, characters or tokens.[/INST]"
          # prompt: "Return the capital letter two places ahead of the letter in the English alphabet provided after 'User input: '. If you reach the end of the alphabet, cycle back to the beginning of the alphabet. For invalid input, which would be anything other than a single letter after 'User input: ' simply return 'ERROR'. The output response should only be the letter without any additional characters, tokens, or whitespace, or ERROR in case of invalid input.",
          knowledge: ""
        },
        %Agent{
          name: :verifier_agent,
          serving: text_generation,
          prompt: "Return 'TRUE' if input is 'G', otherwise return 'FALSE'",
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

    @tag timeout: :infinity
    test "message sequence without job" do
      input = "D"

      %{results: [%{text: text0}]} = Agens.message(:first_agent, input)
      input1 = post_process(text0)
      assert input1 == "C"
      %{results: [%{text: text1}]} = Agens.message(:second_agent, input1)
      input2 = post_process(text1)
      assert input2 == "E"
      %{results: [%{text: text2}]} = Agens.message(:verifier_agent, input2)
      verify1 = post_process(text2)
      assert verify1 == "FALSE"

      %{results: [%{text: text3}]} = Agens.message(:first_agent, input2)
      input4 = post_process(text3)
      assert input4 == "D"
      %{results: [%{text: text4}]} = Agens.message(:second_agent, input4)
      input5 = post_process(text4)
      assert input5 == "F"
      %{results: [%{text: text5}]} = Agens.message(:verifier_agent, input5)
      verify2 = post_process(text5)
      assert verify2 == "FALSE"

      %{results: [%{text: text6}]} = Agens.message(:first_agent, input5)
      input7 = post_process(text6)
      assert input7 == "E"
      %{results: [%{text: text7}]} = Agens.message(:second_agent, input7)
      input8 = post_process(text7)
      assert input8 == "G"
      %{results: [%{text: text8}]} = Agens.message(:verifier_agent, input8)
      verify3 = post_process(text8)
      assert verify3 == "TRUE"
    end

    test "invalid message returns error" do
      msg = "Here is some invalid input"

      %{results: [%{text: text}]} = Agens.message(:second_agent, msg)

      assert text == "ERROR"
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
            agent: :first_agent,
            prompt: "",
            conditions: ""
          },
          %Job.Step{
            agent: :second_agent,
            prompt: "",
            conditions: ""
          },
          %Job.Step{
            agent: :verifier_agent,
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
