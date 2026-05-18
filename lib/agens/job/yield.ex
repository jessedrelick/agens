defmodule Agens.Job.Yield do
  @moduledoc false

  @type thread_id :: binary()
  @type next_node_id :: any()
  @type thread :: {thread_id(), next_node_id()}

  @type t :: %__MODULE__{
          threads: list(thread_id()),
          ready: list(thread())
        }

  @enforce_keys []
  defstruct threads: [], ready: []

  def new(), do: %__MODULE__{}

  def ready?(%__MODULE__{threads: threads, ready: ready}) do
    ready_map = Enum.into(ready, %{})
    Enum.all?(threads, &Map.has_key?(ready_map, &1))
  end

  def thread_ready(nil, thread_id, next_node_id),
    do: thread_ready(%__MODULE__{}, thread_id, next_node_id)

  def thread_ready(%__MODULE__{} = yield, thread_id, next_node_id) do
    Map.update(yield, :ready, [], &[{thread_id, next_node_id} | &1])
  end

  def thread_add(nil, thread_id), do: thread_add(%__MODULE__{}, thread_id)

  def thread_add(%__MODULE__{} = yield, thread_id) do
    Map.update(yield, :threads, [thread_id], &[thread_id | &1])
  end

  def thread_done(nil, _thread_id), do: %__MODULE__{}

  def thread_done(%__MODULE__{} = yield, thread_id) do
    Map.update(yield, :threads, [], &List.delete(&1, thread_id))
  end
end
