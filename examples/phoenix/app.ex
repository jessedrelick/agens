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

  on_mount {AgensDemo.LogHook, :default}

  @pubsub AgensDemo.PubSub
  @topic_prefix "agens"

  @serving_config %Agens.Serving.Config{name: :demo_serving, serving: AgensDemo.InstructorServing}

  @impl true
  def mount(_params, _session, socket) do
    ready =
      if connected?(socket) do
        case Agens.Serving.start(@serving_config) do
          {:ok, _} -> true
          {:error, {:already_started, _}} -> true
        end
      else
        false
      end

    {:ok, assign(socket, topic: "", running: false, result: nil, ready: ready)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={not @ready} class="fixed inset-0 bg-black/50 z-50"></div>
    <div class="min-h-screen bg-gray-50 flex items-start justify-center gap-6 px-10 py-10 antialiased">
      <div class="flex flex-col w-1/2 gap-4">
        <h2 class="text-xl font-semibold text-gray-700">Agens Demo</h2>
        <form phx-submit="run" class="flex flex-col gap-2">
          <input
            class="block w-full p-2.5 bg-white border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 disabled:bg-gray-100"
            type="text"
            name="topic"
            placeholder="Enter a topic for an industry brief..."
            value={@topic}
            disabled={@running}
          />
          <button
            type="submit"
            class="px-5 py-2.5 text-white bg-blue-700 font-medium rounded-lg text-sm hover:bg-blue-800 focus:ring-4 focus:ring-blue-300 disabled:bg-gray-400"
            disabled={@running}
          >
            <%= if @running, do: "Generating...", else: "Generate Brief" %>
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
  def handle_event("run", %{"topic" => topic}, socket) when topic != "" do
    run_id = AgensDemo.Job.new_run_id()
    Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}:#{run_id}")

    case AgensDemo.Job.run(run_id, topic) do
      :ok -> {:noreply, assign(socket, topic: topic, running: true, logs: [], result: nil)}
      {:error, _reason} -> {:noreply, socket}
    end
  end

  def handle_event("run", _, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:node_result, %Message{result: result}}, socket) do
    {:noreply, assign(socket, result: result)}
  end

  @impl true
  def handle_info({:job_complete, _run_id}, socket) do
    {:noreply, assign(socket, running: false)}
  end

  @impl true
  def handle_info({:job_error, %Message{}, _error}, socket) do
    {:noreply, assign(socket, running: false)}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}
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
