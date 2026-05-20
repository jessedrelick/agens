defmodule Test.Support.SubRoutingServing do
  @moduledoc """
  Test Serving used on a Sub-bearing Node to demonstrate `handle_sub/3`
  producing dynamic routing from a resolved Sub-Job.
  """

  use Agens.Serving

  alias Agens.{Message, Serving.Result}

  @impl true
  def start(state), do: {:ok, state}

  @impl true
  def handle_message(_state, _msg, _schema), do: {:ok, %Result{body: ""}}

  @impl true
  def handle_result({:ok, %Result{} = r}, _state, _msg), do: {:ok, r}

  @impl true
  def handle_sub(_state, %Message{result: sub_result}, %Message{} = _parent_node_message) do
    {:ok,
     %Result{
       body: sub_result,
       outputs: %{},
       next: [{:route, "node_1", 1}]
     }}
  end
end
