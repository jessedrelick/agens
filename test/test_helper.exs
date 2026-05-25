backends = [
  Test.Support.Backend
  # Agens.Backend.Emit
  # Agens.Backend.Log
]

Application.put_env(:agens, :backends, backends)
ExUnit.start()
