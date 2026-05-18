defmodule Agens.Job.State do
  @moduledoc false

  alias Agens.Job.{Config, Sub}
  alias Agens.Job.Node, as: JobNode
  alias Agens.Message

  @type t :: %__MODULE__{
          status: :init | :running | :error | :complete | :ended | :stopped,
          config: Config.t(),
          caller: pid() | nil,
          run_id: String.t() | nil,
          sub: Sub.t() | nil,
          thread_count: non_neg_integer(),
          tasks: %{
            Task.ref() => Message.t()
          }
        }

  @enforce_keys [:status, :config]
  defstruct [
    :status,
    :config,
    :caller,
    :run_id,
    :sub,
    :yield,
    tasks: %{},
    thread_count: 0
  ]

  @spec get_message(t(), Task.ref()) :: Message.t() | nil
  def get_message(%__MODULE__{} = state, ref) do
    state
    |> Map.get(:tasks)
    |> Map.get(ref)
  end

  @spec add_task(t(), Task.ref(), Message.t()) :: t()
  def add_task(%__MODULE__{} = state, ref, %Message{} = message) do
    Map.update!(state, :tasks, fn val -> Map.put(val, ref, message) end)
  end

  @spec remove_task(t(), Task.ref()) :: t()
  def remove_task(%__MODULE__{} = state, ref) do
    Map.update!(state, :tasks, fn val -> Map.delete(val, ref) end)
  end

  @spec get_node(t(), any()) :: JobNode.t() | nil
  def get_node(%__MODULE__{config: job_config}, node_id) do
    Map.get(job_config.nodes, node_id)
  end

  @spec change_status(t(), atom()) :: t()
  def change_status(%__MODULE__{} = state, status) when is_atom(status) do
    %__MODULE__{state | status: status}
  end
end
