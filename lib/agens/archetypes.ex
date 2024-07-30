defmodule Agens.Archetypes do
  @auth_token System.get_env("HF_AUTH_TOKEN")

  def text_generation() do
    repo = {:hf, "mistralai/Mistral-7B-Instruct-v0.2", auth_token: @auth_token}

    {:ok, model} = Bumblebee.load_model(repo, type: :bf16)
    {:ok, tokenizer} = Bumblebee.load_tokenizer(repo)
    {:ok, generation_config} = Bumblebee.load_generation_config(repo)

    Bumblebee.Text.generation(model, tokenizer, generation_config)
  end
end
