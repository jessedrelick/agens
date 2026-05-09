Application.put_env(:agens_demo, AgensDemo.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 8080],
  server: true,
  live_view: [signing_salt: "agensdemo"],
  secret_key_base: String.duplicate("a", 64)
)

Application.put_env(:agens, :backends, [Agens.Backend.Log, AgensDemo.PubSubBackend])

Mix.install([
  {:plug_cowboy, "~> 2.7"},
  {:phoenix, "1.7.10"},
  {:phoenix_live_view, "0.20.1"},
  {:instructor, "~> 0.1.0"},
  {:hermes_mcp, "~> 0.14.1"},
  {:agens, path: Path.expand("..", __DIR__)}
])

Code.require_file("servings/instructor_params.ex", __DIR__)
Code.require_file("backends/pubsub.ex", __DIR__)
Code.require_file("mcp/tools.ex", __DIR__)
Code.require_file("mcp/resources.ex", __DIR__)
Code.require_file("mcp/server.ex", __DIR__)
Code.require_file("mcp/client.ex", __DIR__)
Code.require_file("history.ex", __DIR__)
Code.require_file("phoenix/job.ex", __DIR__)
Code.require_file("phoenix/log_hook.ex", __DIR__)
Code.require_file("router/edge_router.ex", __DIR__)
Code.require_file("router/linear_router.ex", __DIR__)
Code.require_file("servings/instructor_serving.ex", __DIR__)
Code.require_file("phoenix/app.ex", __DIR__)

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: AgensDemo.PubSub},
      Hermes.Server.Registry,
      {AgensDemo.MCPServer, transport: {:streamable_http, start: true}},
      {Agens.Supervisor, name: Agens.Supervisor},
      AgensDemo.Endpoint,
      {AgensDemo.MCPClient, transport: {:streamable_http, base_url: "http://localhost:8080", mcp_path: "/mcp"}}
    ],
    strategy: :one_for_one
  )

Process.sleep(:infinity)
