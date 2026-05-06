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

# Requires OPENAI_API_KEY environment variable
Application.put_env(:agens, :backends, [Agens.Backend.Log, AgensDemo.PubSubBackend])

Mix.install([
  {:plug_cowboy, "~> 2.7"},
  {:phoenix, "1.7.10"},
  {:phoenix_live_view, "0.20.1"},
  {:instructor, "~> 0.1.0"},
  {:hermes_mcp, "~> 0.14.1"},
  {:agens, path: Path.expand("..", __DIR__)}
])

Code.require_file("servings/instructor_serving.ex", __DIR__)
Code.require_file("backends/pubsub.ex", __DIR__)
Code.require_file("mcp/tools.ex", __DIR__)
Code.require_file("mcp/resources.ex", __DIR__)
Code.require_file("mcp/server.ex", __DIR__)
Code.require_file("mcp/client.ex", __DIR__)

# ===========================================================================
# Job configuration
# ===========================================================================

defmodule AgensDemo.Job do
  alias Agens.{Job, Message}

  @jobs_dir Path.expand("jobs", __DIR__)

  def load(name) do
    json =
      Path.join(@jobs_dir, "#{name}.json")
      |> File.read!()
      |> Jason.decode!()

    {to_config(json), Map.fetch!(json, "first_node"), build_router(json)}
  end

  def new_run_id do
    Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  def run(run_id, input) do
    {config, first_node} = Application.fetch_env!(:agens_demo, :job)

    with {:ok, _pid} <- Job.start(config, run_id),
         :ok <- Job.run(run_id, input, first_node, []) do
      :ok
    end
  end

  defp to_config(%{"id" => id, "nodes" => nodes} = json) do
    %Job.Config{
      id: id,
      description: Map.get(json, "description"),
      max_retries: Map.get(json, "max_retries", 3),
      nodes:
        Map.new(nodes, fn {node_id, node} ->
          {node_id,
           %Job.Node{
             agent_id: Map.get(node, "agent_id"),
             serving: node |> Map.fetch!("serving") |> String.to_atom(),
             objective: Map.get(node, "objective")
           }}
        end)
    }
  end

  defp build_router(json) do
    routes =
      Map.new(json["nodes"], fn {id, node} ->
        next =
          case Map.get(node, "next") do
            nil -> [:end]
            next_id -> [{:route, next_id, 1}]
          end

        {id, next}
      end)

    fn %Message{node_id: node_id} -> Map.get(routes, node_id, [:end]) end
  end
end

# ===========================================================================
# Phoenix application
# ===========================================================================

defmodule AgensDemo.Layouts do
  use Phoenix.Component

  def render("live.html", assigns) do
    ~H"""
    <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.10/priv/static/phoenix.min.js">
    </script>
    <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.1/priv/static/phoenix_live_view.min.js">
    </script>
    <script>
      const liveSocket = new window.LiveView.LiveSocket("/live", window.Phoenix.Socket);
      liveSocket.connect();
    </script>
    <script src="https://cdn.tailwindcss.com">
    </script>
    <%= @inner_content %>
    """
  end
end

defmodule AgensDemo.ErrorView do
  def render(_, _), do: "error"
end

defmodule AgensDemo.MainLive do
  use Phoenix.LiveView, layout: {AgensDemo.Layouts, :live}

  alias Agens.Message

  @pubsub AgensDemo.PubSub
  @topic_prefix "agens"

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       topic: "",
       running: false,
       logs: [],
       result: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-50 flex items-start justify-center gap-6 px-10 py-10 antialiased">
      <div class="flex flex-col w-1/2 gap-4">
        <h2 class="text-xl font-semibold text-gray-700">Agens Demo</h2>
        <form phx-submit="research" class="flex flex-col gap-2">
          <input
            class="block w-full p-2.5 bg-white border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 disabled:bg-gray-100"
            type="text"
            name="topic"
            placeholder="Enter a research topic..."
            value={@topic}
            disabled={@running}
          />
          <button
            type="submit"
            class="px-5 py-2.5 text-white bg-blue-700 font-medium rounded-lg text-sm hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 disabled:bg-gray-400"
            disabled={@running}
          >
            <%= if @running, do: "Researching...", else: "Research" %>
          </button>
        </form>
        <%= if @result do %>
          <div class="mt-2">
            <h3 class="text-sm font-semibold text-gray-600 mb-1">Result</h3>
            <div class="p-3 bg-white border border-gray-200 rounded-lg text-gray-800 text-sm whitespace-pre-wrap">
              <%= @result %>
            </div>
          </div>
        <% end %>
      </div>
      <div class="flex flex-col w-1/2 gap-2">
        <h3 class="text-sm font-semibold text-gray-600">Logs</h3>
        <div class="p-3 bg-gray-100 rounded-lg min-h-[200px] font-mono text-xs text-gray-600 flex flex-col gap-1">
          <%= if @logs == [] do %>
            <span class="text-gray-400">No activity yet.</span>
          <% else %>
            <div :for={log <- Enum.reverse(@logs)}><%= log %></div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("research", %{"topic" => topic}, socket) when topic != "" do
    run_id = AgensDemo.Job.new_run_id()
    Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}:#{run_id}")

    case AgensDemo.Job.run(run_id, topic) do
      :ok ->
        {:noreply, assign(socket, topic: topic, running: true, logs: [], result: nil)}

      {:error, reason} ->
        {:noreply, add_log(socket, "Error: #{inspect(reason)}")}
    end
  end

  def handle_event("research", _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:job_started, run_id}, socket) do
    {:noreply, add_log(socket, "Job started (#{run_id})")}
  end

  @impl true
  def handle_info({:job_status, _run_id, status}, socket) do
    {:noreply, add_log(socket, "Status: #{status}")}
  end

  @impl true
  def handle_info({:node_started, %Message{agent_id: agent_id}}, socket) do
    {:noreply, add_log(socket, "Agent started: #{agent_id}")}
  end

  @impl true
  def handle_info({:node_retry, %Message{agent_id: agent_id}}, socket) do
    {:noreply, add_log(socket, "Agent retrying: #{agent_id}")}
  end

  @impl true
  def handle_info({:node_result, %Message{agent_id: agent_id, result: result}}, socket) do
    preview = result |> String.slice(0, 80) |> then(&if String.length(result) > 80, do: &1 <> "…", else: &1)
    socket = add_log(socket, "Agent result: #{agent_id}: #{preview}")
    {:noreply, assign(socket, result: result)}
  end

  @impl true
  def handle_info({:job_complete, _run_id}, socket) do
    {:noreply, socket |> add_log("Job complete") |> assign(running: false)}
  end

  @impl true
  def handle_info({:tool_call, _job_id, _run_id, tool_name}, socket) do
    {:noreply, add_log(socket, "Tool call: #{tool_name}")}
  end

  @impl true
  def handle_info({:yield_wait, %Message{agent_id: agent_id}, total, ready}, socket) do
    {:noreply, add_log(socket, "Yield waiting (#{agent_id}): #{ready}/#{total}")}
  end

  @impl true
  def handle_info({:yield_done, %Message{agent_id: agent_id}, total}, socket) do
    {:noreply, add_log(socket, "Yield done (#{agent_id}): #{total}")}
  end

  @impl true
  def handle_info({:job_error, %Message{} = message, error}, socket) do
    socket =
      socket
      |> add_log("Error on #{message.agent_id}: #{inspect(error)}")
      |> assign(running: false)

    {:noreply, socket}
  end

  defp add_log(socket, msg) do
    update(socket, :logs, &[msg | &1])
  end
end

defmodule AgensDemo.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

  forward("/mcp", Hermes.Server.Transport.StreamableHTTP.Plug, server: AgensDemo.MCPServer)

  scope "/", AgensDemo do
    pipe_through(:browser)

    live("/", MainLive, :index)
  end
end

defmodule AgensDemo.Endpoint do
  use Phoenix.Endpoint, otp_app: :agens_demo

  socket("/live", Phoenix.LiveView.Socket)
  plug(AgensDemo.Router)
end

# ===========================================================================
# Start
# ===========================================================================

{job_config, first_node, router} = AgensDemo.Job.load("research")
Application.put_env(:agens_demo, :job, {job_config, first_node})

source = Application.get_env(:agens_demo, :source, :openai)
model = Application.get_env(:agens_demo, :model)

serving_args =
  [source: source, router: router]
  |> then(fn args -> if model, do: Keyword.put(args, :model, model), else: args end)

serving_config = %Agens.Serving.Config{
  name: :demo_serving,
  serving: AgensDemo.InstructorServing,
  args: serving_args
}

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

{:ok, _} = Agens.Serving.start(serving_config)

Process.sleep(:infinity)
