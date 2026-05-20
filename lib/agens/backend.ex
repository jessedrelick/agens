defmodule Agens.Backend do
  @moduledoc """
  Behaviour for side-effecting backends that observe and extend a running Job.

  A backend receives callbacks for lifecycle events (start, status changes, completion, errors),
  per-Node activity (started, retried, result), tool calls, resource loads, prompt finalization,
  yield coordination, and Sub-Job resolution.

  Backends are configured via the `:backends` application environment key:

      config :agens, backends: [MyApp.LogBackend, MyApp.EmitBackend]

  When unset, Agens defaults to `[Agens.Backend.Emit, Agens.Backend.Log]`. All configured
  backends receive each callback in declaration order.

  ## Implementing a backend

      defmodule MyApp.LogBackend do
        @behaviour Agens.Backend

        @impl true
        def start(_caller, _job_id, run_id), do: IO.puts("started \#{run_id}")

        # ... other callbacks ...
      end

  Most callbacks return `:ok`. `c:sub/2` is special: it returns an `Agens.Job.Sub` struct
  describing a Sub-Job to be started, or `nil` if the backend does not handle that `job_id`.
  Returning `nil` lets a later backend in the list resolve the Sub-Job.
  """

  alias Agens.{Message, Resource}

  @typedoc "A Job identifier."
  @type job_id :: binary()

  @typedoc "A run identifier for a single Job invocation."
  @type run_id :: binary()

  @typedoc "A Node identifier within a Job."
  @type node_id :: binary()

  @typedoc "A Job status atom (e.g. `:running`, `:complete`, `:error`)."
  @type status :: atom()

  @typedoc "Normalized record of a tool call invocation as observed by a backend."
  @type tool_call :: %{
          required(:name) => binary(),
          required(:arguments) => map(),
          required(:result) => any() | nil,
          required(:error) => binary() | nil
        }

  @doc "Invoked when a Job has started."
  @callback start(pid(), job_id(), run_id()) :: :ok

  @doc "Invoked when a Job's status transitions (e.g. `:init` → `:running`)."
  @callback status(pid(), run_id(), status()) :: :ok

  @doc "Invoked when a Job completes successfully."
  @callback complete(pid(), run_id()) :: :ok

  @doc "Invoked when a Job errors out. Receives the failing `Agens.Message` and the error reason."
  @callback error(pid(), Message.t(), any()) :: :ok

  @doc "Invoked when a Node begins processing."
  @callback node_started(pid(), Message.t()) :: :ok

  @doc "Invoked when a Node is being retried."
  @callback node_retry(pid(), Message.t()) :: :ok

  @doc "Invoked when a Node has produced a result from its Serving."
  @callback node_result(pid(), Message.t()) :: :ok

  @doc "Invoked when a tool call has been performed (successfully or not)."
  @callback tool_call(pid(), Message.t(), tool_call()) :: :ok

  @doc "Invoked when a resource has been loaded for a Node."
  @callback resource_load(pid(), Message.t(), Resource.t()) :: :ok

  @doc """
  Invoked with the finalized `Agens.Message` after `Agens.Prompt` has built the system and user prompts.

  Useful for logging, persistence or external prompt-rendering hooks.
  """
  @callback prompt(Message.t()) :: :ok

  @doc "Invoked when a yielding Node is waiting on additional threads to converge."
  @callback yield_wait(pid(), Message.t(), integer(), integer()) :: :ok

  @doc "Invoked when all threads have converged on a yielding Node."
  @callback yield_done(pid(), Message.t(), integer()) :: :ok

  @doc """
  Resolves a Sub-Job declaration to a concrete `Agens.Job.Sub`.

  Backends in the configured list are consulted in order; the first to return a `Sub` wins.
  Backends that don't handle the given `job_id` must return `nil`.
  """
  @callback sub(pid(), job_id()) :: Agens.Job.Sub.t() | nil
end
