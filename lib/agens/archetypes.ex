defmodule Agens.Archetypes do
  def text_generation() do
    {:ok, model} = Bumblebee.load_model({:hf, "openai-community/gpt2"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai-community/gpt2"})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, "openai-community/gpt2"})

    Bumblebee.Text.generation(model, tokenizer, generation_config)
  end
end
