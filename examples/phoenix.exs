Application.put_env(:agens_demo, AgensDemo.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 8080],
  server: true,
  live_view: [signing_salt: "agensdemo"],
  secret_key_base: String.duplicate("a", 64)
)

# Configure provider and model via environment variables.
# AGENS_SOURCE: openai (default), anthropic, gemini, groq, ollama
# AGENS_MODEL:  provider-specific model name (defaults per provider if unset)
Application.put_env(:agens_demo, :source, System.get_env("AGENS_SOURCE", "openai") |> String.to_atom())
Application.put_env(:agens_demo, :model, System.get_env("AGENS_MODEL"))
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
Code.require_file("servings/instructor_serving.ex", __DIR__)
Code.require_file("backends/pubsub.ex", __DIR__)
Code.require_file("mcp/tools.ex", __DIR__)
Code.require_file("mcp/resources.ex", __DIR__)
Code.require_file("mcp/server.ex", __DIR__)
Code.require_file("mcp/client.ex", __DIR__)
Code.require_file("router/edge.ex", __DIR__)
Code.require_file("router/agens_router.ex", __DIR__)
Code.require_file("phoenix/job.ex", __DIR__)
Code.require_file("phoenix/app.ex", __DIR__)

{job_config, first_node} = AgensDemo.Job.load("industry_brief")
Application.put_env(:agens_demo, :job, {job_config, first_node})

source = Application.get_env(:agens_demo, :source, :openai)
model = Application.get_env(:agens_demo, :model)

serving_args =
  [source: source]
  |> then(fn args -> if model, do: Keyword.put(args, :model, model), else: args end)

{:ok, _} =
  Supervisor.start_link(
    [
      {Phoenix.PubSub, name: AgensDemo.PubSub},
      Hermes.Server.Registry,
      {AgensDemo.MCPServer, transport: :streamable_http},
      {Agens.Supervisor, name: Agens.Supervisor},
      AgensDemo.Endpoint
    ],
    strategy: :one_for_one
  )

{:ok, _} =
  AgensDemo.MCPClient.start_link(
    transport: {:streamable_http, base_url: "http://localhost:8080", mcp_path: "/mcp"}
  )

{:ok, _} =
  Agens.Serving.start(%Agens.Serving.Config{
    name: :demo_serving,
    serving: AgensDemo.InstructorServing,
    args: serving_args
  })

Process.sleep(:infinity)
