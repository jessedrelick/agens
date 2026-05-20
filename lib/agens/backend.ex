defmodule Agens.Backend do
  @moduledoc """
  Behaviour for side-effecting backends that observe and extend a running Job.

  A backend receives callbacks for lifecycle events (run, status changes, completion, explicit end,
  errors), per-Node activity (started, retried, result), tool calls, resource loads, prompt
  finalization, yield coordination, and Sub-Job resolution.

  Backends are configured via the `:backends` application environment key:

      config :agens, backends: [MyApp.LogBackend, MyApp.EmitBackend]

  When unset, Agens defaults to `[Agens.Backend.Emit, Agens.Backend.Log]`. All configured
  backends receive each callback in declaration order.

  ## Implementing a backend

      defmodule MyApp.LogBackend do
        @behaviour Agens.Backend

        @impl true
        def run(_caller, _job_id, run_id), do: IO.puts("running \#{run_id}")

        # ... other callbacks ...
      end

  Most callbacks return `:ok`. `c:sub/1` is special: it returns an `Agens.Job.Sub` struct
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

  @typedoc """
  Normalized record of a resource load as observed by a backend.

  `:resource` is the resolved `Agens.Resource` when loading succeeded, or the original
  declaration when it failed (the runtime falls back to the bare resource). `:error` is
  `nil` on success or an inspected error reason string on failure.
  """
  @type resource_load :: %{
          required(:resource) => Resource.t(),
          required(:error) => binary() | nil
        }

  @doc """
  Invoked when a Job begins execution, immediately after `Agens.Job.run/3` is accepted.

  Fires once per Job run, paired with the `[:agens, :job, :run]` telemetry event. Distinct from
  `Agens.Job.start/2` (which only starts the supervised process and emits the `[:agens, :job, :start]`
  telemetry event but no backend callback).
  """
  @callback run(pid(), job_id(), run_id()) :: :ok

  @doc "Invoked when a Job's status transitions (e.g. `:init` → `:running`)."
  @callback status(pid(), run_id(), status()) :: :ok

  @doc """
  Invoked when a Job completes by running every Node to completion (no Node returned `:end`).

  Paired with the `[:agens, :job, :complete]` telemetry event. For Jobs that terminate because a
  Serving's `next` returned `:end`, see `c:ended/2`.
  """
  @callback complete(pid(), run_id()) :: :ok

  @doc """
  Invoked when a Job terminates because a Serving's `next` returned an `:end` instruction.

  Paired with the `[:agens, :job, :end]` telemetry event. Distinct from `c:complete/2`, which fires
  when the Job runs to natural completion of all Nodes.
  """
  @callback ended(pid(), run_id()) :: :ok

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

  @doc "Invoked when a resource has been loaded for a Node (successfully or not)."
  @callback resource_load(pid(), Message.t(), resource_load()) :: :ok

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
  @callback sub(job_id()) :: Agens.Job.Sub.t() | nil
end
