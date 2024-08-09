ExUnit.start()

Supervisor.start_link(
  [
    {Agens.Supervisor, name: Agens.Supervisor}
  ],
  strategy: :one_for_one
)
