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

    require Logger

    def get() do
      __MODULE__
    end

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts, opts)
    end

    def init(opts) do
      {:ok, opts}
    end

    def handle_call({:run, %Agens.Message{}}, _, state) do
      Logger.warning("STUB RUN")
      {:reply, "STUB RUN", state}
    end
  end

  def get(true), do: LLM.get()
  def get(false), do: Stub.get()
end
