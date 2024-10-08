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

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, opts)
    end

    def init(opts) do
      {:ok, opts}
    end

    # Normally a Serving would use `message.prompt` rather than `message.input`
    # The Job or Agent would use config and `message.input` to build `message.prompt`
    # In this case, using `message.input` instead to map to a result simplifies testing
    def handle_call({:run, %Agens.Message{} = message}, _, state) do
      result = Test.Support.Helpers.map_input(message.agent_name, message.input)
      {:reply, result, state}
    end
  end
end
