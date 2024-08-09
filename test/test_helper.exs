ExUnit.start()

Supervisor.start_link(
  [
    {Agens, name: Agens},
    {Registry, keys: :unique, name: Agens.Registry.Agents}
  ],
  strategy: :one_for_one
)
