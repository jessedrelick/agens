defmodule Agens.Message do
  @moduledoc """
  The Message struct defines the details of a message passed between Jobs and Servings.

  A Message accumulates context as it flows through a Job: it carries the user/previous-Node input,
  the prepared system/user prompts, the Serving's result, structured outputs, tool calls/results,
  resources, retry state, and the routing decision for the next hop.

  ## Fields

  ### Identity / lifecycle

    * `:caller` - The pid of the process that invoked `Agens.Job.run/3`. Backends receive this as their first argument so they can fan events back out to the right consumer.
    * `:id` - Per-message identifier. Generated as a hex uid; set to `nil` after a successful Node result so the next Node generates a fresh one.
    * `:run_id` - The Job run identifier this message belongs to.
    * `:parent_run_id` - When the message is part of a Sub-Job run, the `run_id` of the enclosing parent Job.
    * `:thread_id` - Identifier of the parallel thread within the run. New threads are spawned when a `:route` instruction fans out with `count > 1`.

  ### Input / output

    * `:input` - The original input string passed to `Agens.Job.run/3`. Required (`@enforce_keys`). Carried forward unchanged across every Node in the run.
    * `:system` - The prepared system prompt string, populated by the Serving's `c:Agens.Serving.build_prompt/3` callback before inference.
    * `:user` - The prepared user prompt string, populated alongside `:system`.
    * `:result` - The Serving's response body for this Node.
    * `:previous_result` - The `:result` of the previous Node in the Job. `nil` on the starting Node; rolls forward on each `:route` transition. Surfaced in the next prompt under the `Previous Result` prefix.
    * `:outputs` - Map of structured outputs parsed from the Serving's response, keyed by `Agens.Router.Output.key`. Used by `c:Agens.Router.resolve/2` to determine routing.

  ### Job / Node references

    * `:job_id` - The id of the `Agens.Job.Config` this run is executing.
    * `:job_description` - The Job's `:description`, added to the LM prompt under the `Job Description` prefix.
    * `:node_id` - The identifier of the `Agens.Job.Node` currently being processed.
    * `:node_objective` - The Node's `:objective`, added to the LM prompt under the `Node Objective` prefix.
    * `:agent_id` - An opaque identifier passed to `c:Agens.Serving.load_context/2`. Not a process or first-class entity — just a hook for the Serving to resolve agent-specific context.
    * `:serving_name` - The name of the `Agens.Serving` resolved from the Node's `:serving` field; the target of `c:Agens.Serving.handle_message/3` for this Node.

  ### Tools / resources

    * `:tool_defs` - MCP-style tool schemas declared on the Node's `:tools` field, surfaced to the LM under `Tool Definitions`.
    * `:tool_calls` - Tool call requests emitted by the LM. When non-empty, the runtime invokes `c:Agens.Serving.tool_call/3` for each entry and re-runs the Node with results merged in.
    * `:tool_results` - Map of resolved tool results keyed by `tool_call["id"]`. Surfaced to the LM under `Tool Results` on the retry prompt.
    * `:resources` - List of `Agens.Resource` structs declared on the Node, loaded by `c:Agens.Serving.load_resource/3` prior to inference and inlined under `Resources`.

  ### Retry / routing

    * `:retries` - The number of times this Node has been retried in the current run. Capped by `Agens.Job.Config.max_retries`.
    * `:retry_reason` - Optional reason string for the most recent retry, surfaced to the LM under `Retry`.
    * `:next` - List of routing instructions emitted by the Serving's Router (`{:route, node_id, count}`, `{:yield, node_id}`, `{:sub, job_id}`, `:end`, `:retry`, `{:retry, reason}`). Drives the next hop in the Job graph.
  """

  @type t :: %__MODULE__{
          caller: pid() | nil,
          id: binary() | nil,
          run_id: binary() | nil,
          parent_run_id: binary() | nil,
          input: String.t(),
          system: String.t() | nil,
          user: String.t() | nil,
          result: String.t() | nil,
          previous_result: String.t() | nil,
          agent_id: binary() | nil,
          serving_name: atom() | nil,
          job_id: binary() | nil,
          job_description: String.t() | nil,
          node_id: binary() | nil,
          node_objective: String.t() | nil,
          outputs: map() | nil,
          retry_reason: String.t() | nil,
          retries: non_neg_integer(),
          thread_id: binary() | nil,
          tool_defs: list() | nil,
          tool_calls: list() | nil,
          tool_results: map() | nil,
          resources: list(Agens.Resource.t()) | nil,
          next: list(Agens.Serving.Result.next())
        }

  @enforce_keys [:input]
  defstruct [
    :caller,
    :id,
    :run_id,
    :parent_run_id,
    :input,
    :system,
    :user,
    :result,
    :previous_result,
    :agent_id,
    :serving_name,
    :job_id,
    :job_description,
    :node_id,
    :node_objective,
    :outputs,
    :retry_reason,
    :thread_id,
    :tool_defs,
    :tool_calls,
    :tool_results,
    :resources,
    next: [],
    retries: 0
  ]

  alias Agens.Serving

  @doc """
  Sends an `Agens.Message` to an `Agens.Serving`.
  """
  @spec send(t()) :: t() | {:error, atom()} | {:retry, String.t()}
  def send(%__MODULE__{input: input}) when input in ["", nil] do
    {:error, :input_required}
  end

  def send(%__MODULE__{agent_id: nil, serving_name: nil}) do
    {:error, :no_agent_or_serving_name}
  end

  def send(%__MODULE__{} = message) do
    case Serving.run(message) do
      {:error, reason} ->
        {:error, reason}

      {:retry, reason} ->
        {:retry, reason}

      {:ok, %Serving.Result{body: body, outputs: outputs, tool_calls: tool_calls, next: next}} ->
        %__MODULE__{message | result: body, outputs: outputs, tool_calls: tool_calls, next: next}
    end
  end
end
