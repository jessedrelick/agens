defmodule Test.Support.AgentCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Test.Support.AgentCase
      import Test.Support.Helpers
    end
  end

  import Test.Support.Helpers

  alias Agens.{Agent, Message}
  alias Test.Support

  setup_all do
    :meck.new(Agent, [:passthrough])
  end

  def setup_mock(_ctx) do
    :meck.expect(Agent, :message, fn %Message{agent_name: agent_name, input: input} = message ->
      result = map_input(agent_name, input)
      Map.put(message, :result, result)
    end)
  end

  def get_agent_configs() do
    [
      %Agent.Config{
        name: :first_agent,
        serving: :text_generation,
        prompt:
          "Return the capital letter one place before the letter in the English alphabet provided after 'Input: '. If you reach the start of the alphabet, cycle to the end of the alphabet i.e. 'Z'. For invalid input, which would be anything other than a single letter after 'Input: ' simply return 'ERROR'. The output response should only be the letter without any additional characters, tokens, or whitespace, or ERROR in case of invalid input.",
        knowledge: ""
      },
      %Agent.Config{
        name: :second_agent,
        serving: :text_generation,
        prompt: %Agent.Prompt{
          identity:
            "You are an AI agent that takes an input letter of the English alphabet and returns the capital letter two places ahead of the letter. If the input is anything but a single letter, your return 'ERROR'",
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
      %Agent.Config{
        name: :verifier_agent,
        serving: :text_generation,
        prompt: "Return 'TRUE' if input is 'G', otherwise return 'FALSE'",
        knowledge: ""
      },
      %Agent.Config{
        name: :tool_agent,
        serving: :text_generation,
        tool: Support.Tools.NoopTool
      }
    ]
  end
end
