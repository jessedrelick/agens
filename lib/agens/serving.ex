defmodule Agens.Serving do
  @moduledoc """
  The Serving module provides functions for starting, stopping and running Servings.

  A Serving is a module that implements the `Agens.Serving` behaviour and is started as a `GenServer`. Its job is to take a prepared `Agens.Message`, perform LM inference, and return a structured `Agens.Serving.Result`. The actual inference call inside `c:handle_message/3` can target anything — an HTTP API (OpenAI, Anthropic, Ollama, etc), an in-process `Nx.Serving`/`Bumblebee` pipeline, a local rules engine — Agens is unopinionated about the backend.

  A single `Agens.Serving` process can be reused across many `Agens.Job.Node`s and Jobs. In most cases you will only need to start one text-generation Serving to be used by most, if not all, of your Nodes.

  In some cases, you may have additional Servings for more specific use cases such as image generation, speech recognition, etc.

  ## Routing

  A Serving owns routing for any Node that declares it. The router can be the Serving module itself (the "merged" pattern) or a separate module (the "split" pattern):

      # Merged: Serving is its own Router
      defmodule MyServing do
        use Agens.Serving
        use Agens.Router

        # ...handle_message/3, handle_result/3, outputs/1, resolve/2
      end

      # Split: a dedicated Router module reused across Servings
      defmodule MyRouter do
        use Agens.Router
        # outputs/1, resolve/2
      end

      defmodule MyServing do
        use Agens.Serving, router: MyRouter
        # ...handle_message/3, handle_result/3
      end

  When `:router` is omitted it defaults to `__MODULE__`, so merging is the zero-config path.

  After `handle_result/3` or `handle_sub/3` returns a `Result`, the macro auto-invokes the router's `route/1` on the message+outputs **only when the returned `next` is empty/nil**. Callbacks that need to set `next` explicitly (e.g. `:end`, `:retry`) can still do so directly and the router will not override.

  ## Sub-Jobs (`handle_sub/3`)

  When a Node declares both `:serving` and `:sub`, the Sub-Job runs in place of a Serving inference call. Once the Sub completes, the parent invokes `c:handle_sub/3` on the Node's declared Serving to derive the parent Node's `outputs` and `next` from the Sub's final `Agens.Message`.

  The default implementation generates the router's `outputs/1` keys with `nil` values and lets the router's `resolve/2` produce the fallback `next`. Override `c:handle_sub/3` when the Sub's output schema differs from the parent's — typical implementations map the Sub's `outputs`/`body` into the parent's output schema, optionally via an LM call.
  """

  defmodule Config do
    @moduledoc """
    The Config struct represents the configuration for a Serving process.

    ## Fields
    - `:name` - The unique name for the Serving process.
    - `:serving` - The module implementing the `Agens.Serving` behaviour (i.e. one that calls `use Agens.Serving`).
    - `:prefixes` - An `Agens.Prefixes` struct of custom prompt prefixes. If `nil`, the default prefixes returned by `Agens.Prefixes.default/0` will be used.
    - `:args` - Additional arguments passed through to the Serving module on start. Available to the Serving's `c:Agens.Serving.start/1` callback via the initial `state.config.args` and typically used to configure the backend (model name, API base URL, credentials, etc).
    - `:timeout` - Timeout in milliseconds for LM inference. Defaults to `60_000`.
    """

    @type t :: %__MODULE__{
            name: atom(),
            serving: module(),
            args: keyword(),
            prefixes: Agens.Prefixes.t() | nil,
            timeout: non_neg_integer()
          }

    @enforce_keys [:name, :serving]
    defstruct [:name, :serving, :prefixes, args: [], timeout: 60_000]
  end

  defmodule Result do
    @moduledoc """
    The structured result returned from a Serving's `c:Agens.Serving.handle_result/3`
    (or `c:Agens.Serving.handle_sub/3`) callback.

    A `Result` describes the LM-facing response body, the parsed structured outputs,
    any tool calls requested by the LM, and the list of routing instructions for the
    next Node(s).

    ## Fields

      * `:body` - The main response body string. Required.
      * `:outputs` - Map of structured output values keyed by `Agens.Router.Output.key`.
      * `:tool_calls` - List of tool call requests emitted by the LM.
      * `:next` - List of route instructions (`{:route, node_id, count}`, `{:yield, node_id}`,
        `{:sub, job_id}`, `:end`, `:retry`, or `{:retry, reason}`). When empty, the parent
        Serving's Router runs `route/1` against the outputs to produce a fallback list.
    """

    @typedoc "Identifier of a target Node for `:route` / `:yield` instructions."
    @type node_id :: binary()

    @typedoc "Identifier of a target Sub-Job for `:sub` instructions."
    @type job_id :: binary()

    @typedoc "Repetition count for a `:route` instruction (used to fan out to multiple threads)."
    @type count :: integer()

    @typedoc "A single routing instruction."
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
            tool_calls: list(),
            next: list(next())
          }

    @enforce_keys [:body]
    defstruct [:body, next: [], outputs: %{}, tool_calls: []]
  end

  alias Agens.{Message, Prompt, Schema}

  @typedoc """
  The internal state passed to every Serving callback.

  Always a map containing at least `:config` (the `Agens.Serving.Config` the Serving was started
  with). Additional keys are managed by the macro injected by `use Agens.Serving` (queue, counters,
  etc) and may be augmented by `c:start/1`.
  """
  @type state :: %{
          required(:config) => Config.t(),
          optional(atom()) => any()
        }

  @doc """
  Initialization hook called once during `init/1`.

  Receives the initial state (already populated with `:config`, `:queue`, `:count`, and `:limit`)
  and returns `{:ok, state}`. Typical implementations stash provider-specific configuration from
  `state.config.args` (API base URLs, credentials, model identifiers, HTTP clients) into the
  state for use in `c:handle_message/3`.
  """
  @callback start(state()) :: {:ok, state()}

  @doc """
  Performs the LM inference call for a single Node run.

  Receives the current `state`, the prepared `Agens.Message` (with `:system` and `:user` already
  populated by `c:build_prompt/3` and `:agent_id`/`:objective`/etc. carried through from the
  Node), and the JSON `schema` assembled from the Router's declared outputs and the Node's tools.

  The host writes the actual HTTP call (OpenAI, Anthropic, Ollama, etc) or `Nx.Serving` /
  `Bumblebee` invocation here, returning either `{:ok, parsed}` — where `parsed` is whatever
  shape the host wants `c:handle_result/3` to receive — or `{:error, reason}`.
  """
  @callback handle_message(state(), Agens.Message.t(), map()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Validates the parsed LM response and converts it into an `Agens.Serving.Result`.

  Receives the tagged tuple from `c:handle_message/3`, the current `state`, and the `Agens.Message`
  the inference ran against. Returns one of:

    * `{:ok, %Agens.Serving.Result{}}` — the response passed validation; routing continues.
    * `{:retry, reason}` — the response failed validation; the runtime increments the retry
      counter and re-runs the Node with `reason` injected under the `Retry` prefix. Bounded by
      `Agens.Job.Config.max_retries`.
    * `{:error, reason}` — hard error; the Job terminates via the normal error path.

  This is the seam for custom validation — domain-specific business rules, structured-output
  shape checks, downstream API errors that should retry rather than abort.
  """
  @callback handle_result({:ok, term()} | {:error, any()}, state(), Agens.Message.t()) ::
              {:ok, Result.t()} | {:error, any()} | {:retry, String.t()}

  @doc """
  Maps a completed Sub-Job's final message back onto the parent Node's `Agens.Serving.Result`.

  Invoked when a Node declares both `:serving` and `:sub` and the Sub-Job runs in place of
  inference. The first message is the Sub's final `Agens.Message` (with `:result` populated by
  the Sub's last Node); the second is the parent Node's `Agens.Message` at the point the Sub
  was launched.

  Returns `{:ok, %Agens.Serving.Result{}}` populating the parent Node's `outputs` and `next`.
  Typical implementations either reshape the Sub's `outputs` to match the parent's output schema
  directly, or feed the Sub's body into an LM call to derive parent outputs.

  Optional — the default implementation populates `body` from the Sub's `:result` and zeroes
  `outputs` against the router's declared keys, leaving routing to the router's `route/1`
  fallback.
  """
  @callback handle_sub(state(), Agens.Message.t(), Agens.Message.t()) ::
              {:ok, Result.t()} | {:error, any()}

  @doc """
  Loads per-agent context for injection under the `Context` prefix.

  Called before `c:build_prompt/3` on every Node run, with the current `state` and the
  `Agens.Message` (which carries the Node's `:agent_id`). Return a string to surface as context,
  or `nil` to omit the section. Typical uses: per-agent system prompts/personas, retrieved
  memory, and **conversation history for turn-based / multi-turn Servings** — Agens does not
  store messages across runs, so multi-turn flows load prior turns here keyed by `run_id`,
  `parent_run_id`, or an application-defined conversation id carried via `agent_id`.

  Optional — defaults to `nil`.
  """
  @callback load_context(state(), Message.t()) :: String.t() | nil

  @doc """
  Resolves an `Agens.Resource` declared on the Node before inference.

  Called once per declared resource. Receives the current `state`, the `Agens.Resource` struct
  (URI, name, optional description), and the `Agens.Message`. Return the resource with `:content`
  populated — file contents, vector-DB result, MCP `resources/read` response, HTTP GET body, or
  whatever the URI maps to in your application. Loaded content is surfaced under the `Resources`
  prefix in the prompt.

  Optional — defaults to returning the resource unchanged.
  """
  @callback load_resource(state(), Agens.Resource.t(), Message.t()) :: Agens.Resource.t()

  @doc """
  Executes a single tool call requested by the LM.

  Invoked for each entry in the LM response's `tool_calls`. Receives the current `state`, the
  tool-call `args` map (matching the tool's declared parameter schema), and the `Agens.Message`.
  Returns `{tool_id, result}` — where `tool_id` matches the LM's tool-call id and `result` is
  whatever JSON-serializable value should be surfaced under the `Tool Results` prefix on the
  next Node run — or `{:error, reason}` on failure.

  The host writes the actual tool effect: hitting an MCP server, calling an HTTP API,
  executing local code, querying a database.

  Optional — defaults to `{:error, :tool_exec_not_implemented}`.
  """
  @callback tool_call(state(), map(), Message.t()) ::
              {binary() | integer(), any()} | {:error, term()}

  @doc """
  Renders an `Agens.Message` into the `{system, user}` prompt pair sent to the LM.

  Receives the message, the Serving's `Agens.Prefixes`, and any context string returned by
  `c:load_context/2`. The default implementation calls `Agens.Prompt.build/3` and joins each
  section into two heading-prefixed strings — appropriate for OpenAI-style system/user
  concatenation.

  Override for providers that need a different shape, e.g. a chat-message array with role
  labels for Anthropic, multi-turn message lists, or custom delimiters. The two-string return
  contract is fixed; the strings can be whatever the provider's `c:handle_message/3` expects to
  receive on `message.system` / `message.user`.

  Optional — defaults to the heading-and-detail format described above.
  """
  @callback build_prompt(Message.t(), Agens.Prefixes.t(), binary() | nil) ::
              {String.t(), String.t()}

  @doc """
  Builds the full JSON schema sent to the LM for structured-output enforcement.

  Default implementation composes `c:response_schema/1`, `c:outputs_schema/1`, and
  `c:tools_schema/1` into one object: it starts from `response_schema/1`, layers the
  outputs and tools fragments under their declared property keys, and sets `required` to all
  top-level properties (strict-mode compatible).

  Override only when the layered callbacks below can't express the shape you need.

  Optional.
  """
  @callback build_schema(Message.t()) :: map()

  @doc """
  Returns the base response-shape JSON schema (root object passed to `c:build_schema/1`).

  Default is `Agens.Schema.response/0` — a minimal `{type: "object", properties: %{}}` shell
  that `c:build_schema/1` augments with `outputs` and `tool_calls` properties. Override to
  declare additional top-level response fields the LM should emit.

  Optional.
  """
  @callback response_schema(Message.t()) :: map()

  @doc """
  Returns the `{property_key, schema}` pair for the structured-output fragment of the response.

  Default returns `{"outputs", Agens.Schema.outputs()}` — an empty placeholder. Most Servings
  override this to derive a strict schema from the Router's declared `Agens.Router.Output` list
  (see `examples/servings/instructor_serving.ex`).

  Optional.
  """
  @callback outputs_schema(Message.t()) :: {binary(), map()}

  @doc """
  Returns the `{property_key, schema}` pair for the tool-call fragment of the response.

  Default returns `{"tool_calls", Agens.Schema.tools()}`. Override when the Node's tool
  schemas need provider-specific shaping or when the property key needs to match a provider's
  expected tool-call field name.

  Optional.
  """
  @callback tools_schema(Message.t()) :: {binary(), map()}

  @optional_callbacks [
    handle_sub: 3,
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

      if !Module.defines?(__MODULE__, {:handle_sub, 3}) do
        @impl Agens.Serving
        def handle_sub(_state, %Message{result: sub_result}, %Message{} = parent_node_message) do
          router = @__agens_router__

          outputs =
            if Code.ensure_loaded?(router) and function_exported?(router, :outputs, 1) do
              router
              |> apply(:outputs, [parent_node_message])
              |> Map.new(fn %Agens.Router.Output{key: k} -> {k, nil} end)
            else
              %{}
            end

          {:ok,
           %Agens.Serving.Result{
             body: sub_result,
             outputs: outputs,
             next: []
           }}
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
    router = Keyword.get(opts, :router)

    quote do
      use GenServer

      alias Agens.Serving.{Config, Result}

      @behaviour Agens.Serving

      @__agens_router__ unquote(router) || __MODULE__

      @before_compile unquote(__MODULE__)

      # =========================================================================
      # Lifecycle
      # =========================================================================

      @spec child_spec(Config.t()) :: Supervisor.child_spec()
      def child_spec(%Config{} = config) do
        %{
          id: config.name,
          start: {__MODULE__, :start_link, [config]}
        }
      end

      @spec start_link(Config.t()) :: GenServer.on_start()
      def start_link(%Config{} = config) do
        config =
          if is_nil(config.prefixes) do
            Map.put(config, :prefixes, Agens.Prefixes.default())
          else
            config
          end

        opts = Keyword.put(config.args, :name, config.name)
        :telemetry.execute([:agens, :serving, :start], %{}, %{name: config.name})
        GenServer.start_link(__MODULE__, config, opts)
      end

      @impl GenServer
      @spec init(Config.t()) :: {:ok, Agens.Serving.state()} | {:stop, term()}
      def init(%Config{} = config) do
        state = %{
          config: config,
          queue: :queue.new(),
          count: 0,
          limit: unquote(limit)
        }

        start(state)
      end

      # =========================================================================
      # GenServer callbacks
      # =========================================================================

      @impl GenServer
      def handle_call(:get_config, _from, state) do
        {:reply, state.config, state}
      end

      @impl GenServer
      def handle_call({:load_resource, resource, message}, from, state) do
        async_reply(from, fn -> load_resource(state, resource, message) end)
        {:noreply, state}
      end

      @impl GenServer
      def handle_call({:tool_call, args, message}, from, state) do
        async_reply(from, fn -> tool_call(state, args, message) end)
        {:noreply, state}
      end

      @impl GenServer
      def handle_call({:handle_sub, sub_message, parent_node_message}, from, state) do
        async_reply(from, fn ->
          :telemetry.execute([:agens, :sub, :handle], %{}, %{
            name: state.config.name,
            run_id: sub_message.run_id,
            parent_run_id: parent_node_message.run_id
          })

          state
          |> handle_sub(sub_message, parent_node_message)
          |> maybe_route(parent_node_message)
        end)

        {:noreply, state}
      end

      @impl GenServer
      def handle_call({:run, msg}, from, state) do
        queue = :queue.in({msg, from}, state.queue)
        state = Map.put(state, :queue, queue)
        :telemetry.execute([:agens, :serving, :enqueue], %{}, %{name: state.config.name})

        maybe_execute(state)
      end

      @impl GenServer
      def handle_info(:result, state) do
        state = Map.update!(state, :count, &max(&1 - 1, 0))

        maybe_execute(state)
      end

      # =========================================================================
      # Agens.Serving callbacks
      # =========================================================================

      @impl Agens.Serving
      def response_schema(%Message{}), do: Schema.response()

      @impl Agens.Serving
      def outputs_schema(%Message{}), do: {"outputs", Schema.outputs()}

      @impl Agens.Serving
      def tools_schema(%Message{}), do: {"tool_calls", Schema.tools()}

      defoverridable response_schema: 1, outputs_schema: 1, tools_schema: 1

      # =========================================================================
      # Private helpers
      # =========================================================================

      defp async_reply(from, fun) do
        Task.Supervisor.start_child(Agens.JobSupervisor, fn ->
          GenServer.reply(from, fun.())
        end)
      end

      defp maybe_execute(%{count: count, limit: limit} = state) when count < limit do
        {:noreply, do_execute(state)}
      end

      defp maybe_execute(state) do
        {:noreply, state}
      end

      defp do_execute(state) do
        case :queue.out(state.queue) do
          {{:value, {msg, from}}, queue} ->
            state = Map.put(state, :queue, queue)

            do_execute(state, msg, from)

          {:empty, _} ->
            state
        end
      end

      defp do_execute(state, message, from) do
        pid = self()

        Task.Supervisor.start_child(Agens.JobSupervisor, fn ->
          :telemetry.span([:agens, :serving, :result], %{}, fn ->
            context = load_context(state, message)
            {system, user} = build_prompt(message, state.config.prefixes, context)

            msg = message |> Map.put(:system, system) |> Map.put(:user, user)

            Agens.backends(:prompt, [msg])

            schema = build_schema(msg)

            task =
              Task.Supervisor.async_nolink(Agens.JobSupervisor, fn ->
                state
                |> handle_message(msg, schema)
                |> handle_result(state, msg)
                |> maybe_route(msg)
              end)

            result =
              case Task.yield(task, state.config.timeout) || Task.shutdown(task) do
                {:ok, val} -> val
                {:exit, reason} -> {:error, reason}
                nil -> {:error, :timeout}
              end

            GenServer.reply(from, result)
            send(pid, :result)

            {:ok, %{name: msg.serving_name}}
          end)
        end)

        Map.update!(state, :count, &(&1 + 1))
      end

      defp maybe_route({:ok, %Result{next: next} = result}, %Message{} = msg)
           when next in [nil, []] do
        router = @__agens_router__

        if Code.ensure_loaded?(router) and function_exported?(router, :route, 1) do
          routed_next = apply(router, :route, [%Message{msg | outputs: result.outputs}])
          {:ok, %Result{result | next: routed_next}}
        else
          {:ok, result}
        end
      end

      defp maybe_route(other, _msg), do: other
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
      :telemetry.execute([:agens, :serving, :stop], %{}, %{name: name})
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

  @doc false
  @spec call_tool(atom(), map(), Message.t()) :: {binary() | integer(), any()} | {:error, term()}
  def call_tool(serving_name, args, message) when is_atom(serving_name) do
    serving_name
    |> Agens.serving_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:tool_call, args, message}, :infinity)
    end)
  end

  @doc false
  @spec load_resource(atom(), Agens.Resource.t(), Message.t()) ::
          {:ok, Agens.Resource.t()} | {:error, term()}
  def load_resource(serving_name, resource, message) when is_atom(serving_name) do
    Agens.serving_pid(serving_name, {:error, :serving_not_found}, fn pid ->
      {:ok, GenServer.call(pid, {:load_resource, resource, message}, :infinity)}
    end)
  end

  @doc """
  Executes an `Agens.Message` against an `Agens.Serving`
  """
  @spec run(Message.t()) :: {:ok, Result.t()} | {:error, term()} | {:retry, String.t()}
  def run(%Message{serving_name: name} = message) when is_atom(name) do
    name
    |> Agens.serving_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:run, message}, :infinity)
    end)
  end

  @doc false
  @spec handle_sub(atom(), Message.t(), Message.t()) ::
          {:ok, Result.t()} | {:error, term()}
  def handle_sub(serving_name, %Message{} = sub_message, %Message{} = parent_node_message)
      when is_atom(serving_name) do
    serving_name
    |> Agens.serving_pid({:error, :serving_not_found}, fn pid ->
      GenServer.call(pid, {:handle_sub, sub_message, parent_node_message}, :infinity)
    end)
  end
end
