defmodule Agens.Message do
  @moduledoc """
  The Message struct defines the details of a message passed between Jobs and Servings.

  ## Fields

    * `:parent_pid` - The process identifier of the parent/caller process.
    * `:input` - The input string for the message. Required.
    * `:prompt` - The final prompt string constructed for `Agens.Serving.run/1`.
    * `:result` - The result string for the message.
    * `:agent_id` - An identifier passed to `c:Agens.Serving.load_context/2` so the Serving can resolve agent-specific context for the message. Not a process or first-class entity - just an opaque identifier interpreted by the Serving.
    * `:serving_name` - The name of the `Agens.Serving`.
    * `:job_name` - The name of the `Agens.Job`.
    * `:job_description` - The description of the `Agens.Job` to be added to the LM prompt.
    * `:step_index` - The index of the `Agens.Job.Step`.
    * `:step_objective` - The objective of the `Agens.Job.Step` to be added to the LM prompt.
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
          agent_id: any() | nil,
          serving_name: atom() | nil,
          job_id: binary() | nil,
          job_description: String.t() | nil,
          node_id: any(),
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
