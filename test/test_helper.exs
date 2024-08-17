Supervisor.start_link(
  [
    {Agens.Supervisor, name: Agens.Supervisor}
  ],
  strategy: :one_for_one
)

%Agens.Serving.Config{
  name: :text_generation,
  serving: Test.Support.Serving.Stub
}
|> Agens.Serving.start()

:meck.new(Agent, [:passthrough])

ExUnit.start(exclude: [:lm])
