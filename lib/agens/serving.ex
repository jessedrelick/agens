defmodule Agens.Serving do
  @moduledoc """
  The Serving module provides functions for starting, stopping and running Servings.

  `Agens.Serving` accepts a `GenServer` module or `Nx.Serving` struct for processing messages.

  `Agens.Serving` is decoupled from `Agens.Agent` in order to reuse a single LM across multiple agents. In most cases, however, you will only need to start one text generation serving to be used by most, if not all, agents.

  In some cases, you may have additional servings for more specific use cases such as image generation, speech recognition, etc.

  Servings were built with the `Bumblebee` library in mind, as well as `Nx.Serving`. `GenServer` is supported for working with LM APIs instead, which may be more cost effective and easier to get started with.
  """

  defmodule Config do
    @moduledoc """
    The Config struct represents the configuration for a Serving process.

    ## Fields
    - `:name` - The unique name for the Serving process.
    - `:serving` - The `Nx.Serving` struct or `GenServer` module for the `Agens.Serving`.
    - `:prefixes` - An `Agens.Prefixes` struct of custom prompt prefixes. If `nil`, default prompt prefixes will be used instead. Default prompt prefixes can also be overridden by using the `prefixes` options in `Agens.Supervisor`.
    - `:finalize` - A function that accepts the prepared prompt (including any applied prefixes) and returns a modified version of the prompt. Useful for wrapping the prompt or applying final processing before sending to the LM for inference. If `nil`, the prepared prompt will be used as-is.
    - `:args` - Additional arguments to be passed to the `Nx.Serving` or `GenServer` module. See the [Nx.Serving](https://hexdocs.pm/nx/Nx.Serving.html) or [GenServer](https://hexdocs.pm/elixir/GenServer.html) documentation for more information.
    """

    @type t :: %__MODULE__{
            name: atom(),
            serving: module(),
            args: keyword(),
            prefixes: Agens.Prefixes.t() | nil
          }

    @enforce_keys [:name, :serving]
    defstruct [:name, :serving, :prefixes, args: []]
  end

  defmodule Result do
    @type node_id :: any()
    @type job_id :: any()
    @type count :: integer()
    @type next ::
            {:route, node_id(), count()}
            | {:yield, node_id()}
            | {:sub, job_id()}
            | :end
            | :retry
            | {:retry, String.t()}
    @type t :: %__MODULE__{
            body: String.t(),
            outputs: map(),
            tool_calls: map(),
            next: list(next())
          }

    @enforce_keys [:body]
    defstruct [:body, next: [], outputs: %{}, tool_calls: %{}]
  end

  defmodule State do
    @moduledoc false

    @type t :: %{
            required(:config) => Config.t(),
            optional(atom()) => any()
          }
  end

  alias Agens.{Message, Prompt, Schema}

  @callback start(State.t()) :: {:ok, State.t()}
  @callback handle_message(State.t(), Agens.Message.t(), map()) ::
              {:ok, term()} | {:error, term()}
  @callback handle_result({:ok, term()} | {:error, any()}, State.t(), Agens.Message.t()) ::
              {binary(), map()} | {:error, any()} | {:retry, String.t()}

  @callback load_context(State.t(), Message.t()) :: String.t() | nil
  @callback load_resource(State.t(), Agens.Resource.t(), Message.t()) :: Agens.Resource.t()
  @callback tool_call(State.t(), map(), Message.t()) :: {binary() | integer(), any()}
  @callback build_prompt(Message.t(), Agens.Prefixes.t(), binary() | nil) ::
              {String.t(), String.t()}
  @callback build_schema(Message.t()) :: map()
  @callback response_schema(Message.t()) :: map()
  @callback outputs_schema(Message.t()) :: {binary(), map()}
  @callback tools_schema(Message.t()) :: {binary(), map()}

  @optional_callbacks [
    load_context: 2,
    load_resource: 3,
    tool_call: 3,
    build_schema: 1,
    response_schema: 1,
    outputs_schema: 1,
    tools_schema: 1
  ]

  defmacro __before_compile__(_env) do
    quote do
      if !Module.defines?(__MODULE__, {:load_context, 2}) do
        @impl Agens.Serving
        def load_context(_state, _message), do: nil
      end

      if !Module.defines?(__MODULE__, {:load_resource, 3}) do
        @impl Agens.Serving
        def load_resource(_state, resource, _message), do: resource
      end

      if !Module.defines?(__MODULE__, {:tool_call, 3}) do
        @impl Agens.Serving
        def tool_call(_state, _args, _message), do: {:error, :tool_exec_not_implemented}
      end

      if !Module.defines?(__MODULE__, {:build_prompt, 3}) do
        @impl Agens.Serving
        def build_prompt(%Message{} = message, prefixes, context \\ nil) do
          {system_pairs, user_pairs} = Prompt.build(message, prefixes, context)
          system = system_pairs |> Enum.map(&prompt_field/1) |> Enum.join("\n")
          user = user_pairs |> Enum.map(&prompt_field/1) |> Enum.join("\n")
          {system, user}
        end

        @spec prompt_field({{String.t(), String.t()}, String.t() | map()}) :: String.t()
        defp prompt_field({{heading, detail}, value}) when is_binary(value) do
          """
          ## #{heading}
          #{detail}:

          #{value}
          """
        end

        defp prompt_field({{heading, detail}, value}) when is_map(value) do
          """
          ## #{heading}
          #{detail}:

          #{Jason.encode!(value)}
          """
        end

        defp prompt_field({{heading, detail}, value}) when is_list(value) do
          """
          ## #{heading}
          #{detail}:

          #{Jason.encode!(value)}
          """
        end
      end

      if !Module.defines?(__MODULE__, {:build_schema, 1}) do
        @impl Agens.Serving
        def build_schema(%Message{} = msg) do
          {tools_key, tools} = tools_schema(msg)
          {outputs_key, outputs} = outputs_schema(msg)

          base = response_schema(msg)

          properties =
            base
            |> Map.get("properties", %{})
            |> Map.put(tools_key, tools)
            |> Map.put(outputs_key, outputs)

          base
          |> Map.put("properties", properties)
          |> Map.put("required", Map.keys(properties))
        end
      end

    end
  end

  defmacro __using__(opts) do
    limit = Keyword.get(opts, :limit, 10)

    quote do
      use GenServer

      alias Agens.Serving.{Config, Result}

      @behaviour Agens.Serving

      @before_compile unquote(__MODULE__)

      @spec child_spec(Config.t()) :: Supervisor.child_spec()
      def child_spec(%Config{} = config) do
        %{
          id: config.name,
          start: {__MODULE__, :start_link, [config]}
        }
      end

      @spec start_link(keyword(), Config.t()) :: GenServer.on_start()
      def start_link(extra, %Config{} = config) do
        config =
          if is_nil(config.prefixes) do
            prefixes = Keyword.get(extra, :prefixes, Agens.Prefixes.default())
            Map.put(config, :prefixes, prefixes)
          else
            config
          end

        opts = Keyword.put(config.args, :name, config.name)
        :telemetry.execute([:agens, :serving, :start], %{}, %{name: config.name})
        GenServer.start_link(__MODULE__, config, opts)
      end

      @impl GenServer
      @spec init(Config.t()) :: {:ok, State.t()} | {:stop, term(), State.t()}
      def init(%Config{} = config) do
        state = %{
          config: config,
          queue: :queue.new(),
          count: 0,
          limit: unquote(limit)
        }

        start(state)
      end

      @impl GenServer
      def handle_call(:get_config, _from, state) do
        {:reply, state.config, state}
      end

      @impl GenServer
      def handle_call({:load_resource, resource, message}, _from, state) do
        {:reply, load_resource(state, resource, message), state}
      end

      @impl GenServer
      def handle_call({:tool_call, args, message}, _from, state) do
        {:reply, tool_call(state, args, message), state}
      end

      @impl GenServer
      def handle_call({:run, msg}, from, state) do
        queue = :queue.in({msg, from}, state.queue)
        state = Map.put(state, :queue, queue)
        :telemetry.execute([:agens, :serving, :enqueue], %{}, %{name: msg.agent_id})

        maybe_execute(state)
      end

      @impl GenServer
      def handle_info(:result, state) do
        state = Map.update!(state, :count, &max(&1 - 1, 0))

        maybe_execute(state)
      end

      def maybe_execute(%{count: count, limit: limit} = state) when count < limit do
        {:noreply, do_execute(state)}
      end

      def maybe_execute(state) do
        {:noreply, state}
      end

      def do_execute(state) do
        case :queue.out(state.queue) do
          {{:value, {msg, from}}, queue} ->
            state = Map.put(state, :queue, queue)

            do_execute(state, msg, from)

          {:empty, _} ->
            state
        end
      end

      def do_execute(state, message, from) do
        pid = self()

        Task.Supervisor.start_child(Agens.JobSupervisor, fn ->
          :telemetry.span([:agens, :serving, :result], %{}, fn ->
            context = load_context(state, message)
            {system, user} = build_prompt(message, state.config.prefixes, context)

            msg = message |> Map.put(:system, system) |> Map.put(:user, user)

            Agens.backends(:prompt, [msg])

            schema = build_schema(msg)

            result =
              state
              |> handle_message(msg, schema)
              |> handle_result(state, msg)

            GenServer.reply(from, result)

            {:ok, %{name: msg.serving_name}}
          end)
        end)

        send(pid, :result)
        Map.update!(state, :count, &(&1 + 1))
      end

      @impl Agens.Serving
      def response_schema(%Message{}), do: Schema.response()

      @impl Agens.Serving
      def outputs_schema(%Message{}), do: {"outputs", Schema.outputs()}

      @impl Agens.Serving
      def tools_schema(%Message{}), do: {"tool_calls", Schema.tools()}

      defoverridable response_schema: 1, outputs_schema: 1, tools_schema: 1
    end
  end

  # ===========================================================================
  # Public API
  # ===========================================================================

  @doc """
  Starts an `Agens.Serving` process
  """
  @spec start(Config.t()) :: {:ok, pid()} | {:error, term}
  def start(%Config{} = config) do
    DynamicSupervisor.start_child(Agens, {config.serving, config})
  end

  @doc """
  Stops an `Agens.Serving` process
  """
  @spec stop(atom()) :: :ok | {:error, :serving_not_found}
  def stop(name) when is_atom(name) do
    name
    |> Agens.serving_pid({:error, :serving_not_found}, fn pid ->
      :ok = DynamicSupervisor.terminate_child(Agens, pid)
    end)
  end

  @doc """
  Retrieves the Serving configuration by Serving name or `pid`.
  """
  @spec get_config(atom() | pid()) :: {:ok, Config.t()} | {:error, :serving_not_found}
  def get_config(name) when is_atom(name) do
    name
    |> Agens.serving_pid({:error, :serving_not_found}, fn pid -> get_config(pid) end)
  end

  def get_config(pid) when is_pid(pid) do
    {:ok, GenServer.call(pid, :get_config)}
  end

  @spec call_tool(atom(), map(), Message.t()) :: {binary() | integer(), any()} | {:error, term()}
  def call_tool(serving_name, args, message) when is_atom(serving_name) do
    serving_name
    |> Agens.serving_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:tool_call, args, message}, :infinity)
    end)
  end

  @spec load_resource(atom(), Agens.Resource.t(), Message.t()) :: Agens.Resource.t()
  def load_resource(serving_name, resource, message) when is_atom(serving_name) do
    serving_name
    |> Agens.serving_pid(resource, fn pid ->
      GenServer.call(pid, {:load_resource, resource, message}, :infinity)
    end)
  end

  @doc """
  Executes an `Agens.Message` against an `Agens.Serving`
  """
  @spec run(Message.t()) :: {:ok, Result.t()} | {:error, term()}
  def run(%Message{serving_name: name} = message) when is_atom(name) do
    name
    |> Agens.serving_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:run, message}, :infinity)
    end)
  end
end
