real_llm? = Application.get_env(:agens, :real_llm, false)

Supervisor.start_link(
  [
    {Agens.Supervisor, name: Agens.Supervisor}
  ],
  strategy: :one_for_one
)

%Agens.Serving.Config{
  name: :text_generation,
  serving: Test.Support.Serving.get(real_llm?)
}
|> Agens.Serving.start()

:meck.new(Agent, [:passthrough])

ExUnit.start()
