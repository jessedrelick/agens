defmodule Test.Support.Serving do

  defmodule LLM do
    def get() do
      IO.puts("Enabling EXLA Backend")
      Application.put_env(:nx, :default_backend, EXLA.Backend)
      auth_token = System.get_env("HF_AUTH_TOKEN")
      repo = {:hf, "mistralai/Mistral-7B-Instruct-v0.2", auth_token: auth_token}

      IO.puts("Loading Model")
      {:ok, model} = Bumblebee.load_model(repo, type: :bf16)
      {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
      {:ok, generation_config} = Bumblebee.load_generation_config(repo)

      IO.puts("Starting LLM")
      serving = Bumblebee.Text.generation(model, tokenizer, generation_config)
      IO.puts("LLM Ready")

      serving
    end
  end

  defmodule Stub do
    use GenServer

    def get() do
      __MODULE__
    end

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

    defp map_input(:tool_agent, "E"), do: "FALSE"

    defp map_input(agent, input), do: "sent '#{input}' to: #{agent}"
  end

  def get(true), do: LLM.get()
  def get(false), do: Stub.get()
end
