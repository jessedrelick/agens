Application.put_env(:agens_demo, AgensDemo.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 8080],
  server: true,
  live_view: [signing_salt: "agensdemo"],
  secret_key_base: String.duplicate("a", 64)
)

Mix.install([
  {:plug_cowboy, "~> 2.6"},
  {:phoenix, "1.7.10"},
  {:phoenix_live_view, "0.20.1"},
  {:bumblebee, "~> 0.5.0"},
  {:exla, "~> 0.7.0"},
  {:agens, "~> 0.1.3"}
  # {:agens, path: Path.expand("../agens")}
])

Application.put_env(:nx, :default_backend, EXLA.Backend)

defmodule AgensDemo.CustomServing do
  use GenServer

  alias Agens.{Message, Serving}

  def start_link(args) do
    {config, args} = Keyword.pop(args, :config)
    GenServer.start_link(__MODULE__, config, args)
  end

  def init(%Serving.Config{} = config) do
    {:ok, config}
  end

  @impl true
  def handle_call({:run, %Message{input: input}}, _from, state) do
    result = "RESULT: #{input}"
    {:reply, result, state}
  end
end

defmodule AgensDemo.Layouts do
  use Phoenix.Component

  def render("live.html", assigns) do
    ~H"""
    <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.10/priv/static/phoenix.min.js">
    </script>
    <script
      src="https://cdn.jsdelivr.net/npm/phoenix_live_view@0.20.1/priv/static/phoenix_live_view.min.js"
    >
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

  require Logger

  alias Agens.{Agent, Job, Message, Serving}

  @impl true
  def mount(_params, _session, socket) do
    send(self(), :mounted)

    {:ok,
     assign(socket,
       text: "",
       destination: "nx_serving",
       ready: false,
       result: nil,
       job: nil,
       logs: []
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen w-screen flex items-start justify-center antialiased gap-4 px-10 py-10">
      <div class="flex flex-col w-1/2 gap-2">
        <.heading>Input:</.heading>
        <.input text={@text} destination={@destination} ready={@ready} />
        <.buttons ready={@ready} />
        <.result result={@result} />
      </div>
      <div class="flex flex-col w-1/2 gap-2">
        <.heading>Logs:</.heading>
        <.logs logs={@logs} />
      </div>
    </div>
    """
  end

  attr(:text, :string, required: true)
  attr(:destination, :string, required: true)
  attr(:ready, :boolean, required: true)

  defp input(assigns) do
    ~H"""
    <form phx-change="update_inputs" class="m-0">
      <select name="destination" disabled={@ready != true} class="mb-2 p-2.5 bg-gray-50 border border-gray-300 text-gray-900 disabled:bg-gray-300 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500">
        <option value="nx_serving" selected={@destination == "nx_serving"}>Nx Serving</option>
        <option value="gs_serving" selected={@destination == "gs_serving"}>GenServer Serving</option>
        <option value="invalid_serving" selected={@destination == "invalid_serving"}>Invalid Serving</option>
        <option value="nx_agent" selected={@destination == "nx_agent"}>Nx Agent</option>
        <option value="gs_agent" selected={@destination == "gs_agent"}>GenServer Agent</option>
        <option value="invalid_agent" selected={@destination == "invalid_agent"}>Invalid Agent</option>
      </select>
      <input
        class="block w-full p-2.5 bg-gray-50 border border-gray-300 text-gray-900 disabled:bg-gray-300 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500"
        type="text"
        name="text"
        disabled={@ready != true}
        value={@text}
      />
    </form>
    """
  end

  attr(:ready, :boolean, required: true)

  defp buttons(assigns) do
    ~H"""
    <div>
      <button
        class="px-5 py-2.5 text-center mr-1 inline-flex items-center text-white disabled:bg-gray-300 bg-blue-700 font-medium rounded-lg text-sm hover:bg-blue-800 focus:ring-4 focus:ring-blue-300"
        phx-click="send_message"
        disabled={@ready != true}
      >
        Send Message
      </button>
      <button
        class="px-5 py-2.5 text-center mr-1 inline-flex items-center text-white disabled:bg-gray-300 bg-green-700 font-medium rounded-lg text-sm hover:bg-green-800 focus:ring-4 focus:ring-blue-300"
        phx-click="start_job"
        disabled={@ready != true}
      >
        Start Job
      </button>
    </div>
    """
  end

  attr(:result, :map, required: true)

  defp result(assigns) do
    ~H"""
    <div>
      <.heading>Result:</.heading>
      <.async_result :let={result} assign={@result} :if={@result}>
        <:loading>
          <.spinner />
        </:loading>
        <:failed :let={reason}>
          <pre><%= inspect(reason) %></pre>
        </:failed>
        <p class="text-gray-600 text-md"><%= result %></p>
      </.async_result>
    </div>
    """
  end

  attr(:logs, :list, required: true)

  defp logs(assigns) do
    ~H"""
    <div class="p-2 bg-gray-300">
      <div :for={log <- Enum.reverse(@logs)} class="text-gray-600 text-sm mb-1"><%= log %></div>
    </div>
    """
  end

  slot(:inner_block)

  defp heading(assigns) do
    ~H"""
    <div>
      <h3 class="mt-2 flex space-x-1.5 items-center text-gray-600 text-lg"><%= render_slot(@inner_block) %></h3>
    </div>
    """
  end

  defp spinner(assigns) do
    ~H"""
    <svg
      class="inline mr-2 w-4 h-4 text-gray-200 animate-spin fill-blue-600"
      viewBox="0 0 100 101"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <path
        d="M100 50.5908C100 78.2051 77.6142 100.591 50 100.591C22.3858 100.591 0 78.2051 0 50.5908C0 22.9766 22.3858 0.59082 50 0.59082C77.6142 0.59082 100 22.9766 100 50.5908ZM9.08144 50.5908C9.08144 73.1895 27.4013 91.5094 50 91.5094C72.5987 91.5094 90.9186 73.1895 90.9186 50.5908C90.9186 27.9921 72.5987 9.67226 50 9.67226C27.4013 9.67226 9.08144 27.9921 9.08144 50.5908Z"
        fill="currentColor"
      />
      <path
        d="M93.9676 39.0409C96.393 38.4038 97.8624 35.9116 97.0079 33.5539C95.2932 28.8227 92.871 24.3692 89.8167 20.348C85.8452 15.1192 80.8826 10.7238 75.2124 7.41289C69.5422 4.10194 63.2754 1.94025 56.7698 1.05124C51.7666 0.367541 46.6976 0.446843 41.7345 1.27873C39.2613 1.69328 37.813 4.19778 38.4501 6.62326C39.0873 9.04874 41.5694 10.4717 44.0505 10.1071C47.8511 9.54855 51.7191 9.52689 55.5402 10.0491C60.8642 10.7766 65.9928 12.5457 70.6331 15.2552C75.2735 17.9648 79.3347 21.5619 82.5849 25.841C84.9175 28.9121 86.7997 32.2913 88.1811 35.8758C89.083 38.2158 91.5421 39.6781 93.9676 39.0409Z"
        fill="currentFill"
      />
    </svg>
    """
  end

  @impl true
  def handle_event("update_inputs", %{"text" => text, "destination" => destination}, socket) do
    {:noreply, socket |> assign(text: text, destination: destination)}
  end

  @impl true
  def handle_event("send_message", _, %{assigns: assigns} = socket) do
    name =
      case assigns.destination do
        "invalid_serving" -> :invalid_serving
        "invalid_agent" -> :invalid_agent
        destination -> String.to_existing_atom(destination)
      end

    {key, type} =
      if name in [:nx_agent, :gs_agent, :invalid_agent],
        do: {:agent_name, "agent"},
        else: {:serving_name, "serving"}

    socket =
      socket
      |> assign(:result, nil)
      |> assign_async(:result, fn ->
        %Message{
          input: assigns.text
        }
        |> Map.put(key, name)
        |> Message.send()
        |> case do
          %Message{result: result} -> {:ok, %{result: result}}
          {:error, reason} -> {:error, reason}
        end
      end)
      |> assign(:logs, ["Sent message to #{type}: #{name}" | assigns.logs])

    {:noreply, socket}
  end

  @impl true
  def handle_event("start_job", _, %{assigns: assigns} = socket) do
    name = :my_job

    socket =
      socket
      |> assign(:text, assigns.text)
      |> assign(:result, nil)

    %Job.Config{
      name: name,
      steps: [
        %Job.Step{
          agent: :nx_agent
        },
        %Job.Step{
          agent: :gs_agent
        },
        %Job.Step{
          agent: :nx_agent,
          conditions: %{
            "__DEFAULT__" => :end
          }
        }
      ]
    }
    |> Job.start()
    |> case do
      {:ok, _pid} ->
        send(self(), :job_started)
        {:noreply, socket |> assign(:logs, ["Job started: #{name}" | assigns.logs])}

      {:error, {:already_started, _pid}} ->
        send(self(), :job_started)
        {:noreply, socket |> assign(:logs, ["Job already started: #{name}" | assigns.logs])}
    end
  end

  @impl true
  def handle_info(:job_started, %{assigns: assigns} = socket) do
    name = :my_job

    name
    |> Job.run(assigns.text)
    |> case do
      :ok ->
        {:noreply, socket |> assign(:logs, ["Job running: #{name}" | assigns.logs])}
      {:error, reason} ->
        {:noreply, socket |> assign(:logs, ["Job error: #{name}: #{inspect(reason)}" | assigns.logs])}
    end
  end

  @impl true
  def handle_info(:mounted, %{assigns: assigns} = socket) do
    name_nx = :nx_serving
    name_gs = :gs_serving

    Serving.start(%Serving.Config{
      name: name_nx,
      serving: serving()
    })

    Serving.start(%Serving.Config{
      name: name_gs,
      serving: AgensDemo.CustomServing
    })

    send(self(), :servings_started)

    {:noreply,
     socket |> assign(:logs, ["Servings started: #{name_nx}, #{name_gs}" | assigns.logs])}
  end

  @impl true
  def handle_info(:servings_started, %{assigns: assigns} = socket) do
    name_nx = :nx_agent
    name_gs = :gs_agent

    Agent.start([
      %Agent.Config{
        name: name_nx,
        serving: :nx_serving
      },
      %Agent.Config{
        name: name_gs,
        serving: :gs_serving
      }
    ])

    send(self(), :agents_started)
    {:noreply, socket |> assign(:logs, ["Agents started: #{name_nx}, #{name_gs}" | assigns.logs])}
  end

  @impl true
  def handle_info(:agents_started, %{assigns: assigns} = socket) do
    {:noreply, socket |> assign(:logs, ["Ready" | assigns.logs]) |> assign(:ready, true)}
  end

  # Agens events
  @impl true
  def handle_info({:job_started, job_name}, %{assigns: assigns} = socket) do
    debug("#{job_name} started")
    {:noreply, socket |> assign(:logs, ["Agens event: job_started" | assigns.logs])}
  end

  @impl true
  def handle_info({:step_started, {job_name, step_index}, input}, %{assigns: assigns} = socket) do
    debug("#{job_name} step #{step_index} started with: #{input}")

    {:noreply,
     socket |> assign(:logs, ["Agens event: step_started (#{step_index})" | assigns.logs])}
  end

  @impl true
  def handle_info({:step_result, {job_name, step_index}, result}, %{assigns: assigns} = socket) do
    debug("#{job_name} step #{step_index} result: #{result}")

    {:noreply,
     socket |> assign(:logs, ["Agens event: step_result (#{step_index})" | assigns.logs])}
  end

  @impl true
  def handle_info({:job_ended, job_name, result}, %{assigns: assigns} = socket) do
    debug("#{job_name} ended: #{result}")

    {:noreply,
     socket |> assign(:logs, ["Agens event: job_ended (#{job_name}) #{result}" | assigns.logs])}
  end

  @impl true
  def handle_info({:job_error, {job_name, step_index}, err}, %{assigns: assigns} = socket) do
    debug("#{job_name} error (step #{step_index}): #{inspect(err)}")

    {:noreply,
     socket |> assign(:logs, ["Agens event: job_error (#{job_name}, step #{step_index}) #{inspect(err)}" | assigns.logs])}
  end

  # Helpers
  defp serving() do
    {:ok, gpt2} = Bumblebee.load_model({:hf, "openai-community/gpt2"})
    {:ok, tokenizer} = Bumblebee.load_tokenizer({:hf, "openai-community/gpt2"})
    {:ok, generation_config} = Bumblebee.load_generation_config({:hf, "openai-community/gpt2"})

    Bumblebee.Text.generation(gpt2, tokenizer, generation_config)
  end

  defp debug(msg) do
    Logger.debug(msg)
  end
end

defmodule AgensDemo.Router do
  use Phoenix.Router

  import Phoenix.LiveView.Router

  pipeline :browser do
    plug(:accepts, ["html"])
  end

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

{:ok, _} =
  Supervisor.start_link(
    [
      {Agens.Supervisor, name: Agens.Supervisor},
      AgensDemo.Endpoint
    ],
    strategy: :one_for_one
  )

Process.sleep(:infinity)
