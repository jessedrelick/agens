defmodule Agens.Job.Config do
  @moduledoc """
  The Config struct defines the details of a Job.

  ## Fields
  - `id` - The unique id used to identify the Job.
  - `description` - An optional string to be added to the LM prompt that describes the basic goal of the Job.
  - `nodes` - A list of `Agens.Job.Node` structs that define the sequence of agent actions to be performed.
  """

  alias Agens.Job.Node

  @derive [Jason.Encoder]

  @type t :: %__MODULE__{
          id: binary(),
          description: String.t() | nil,
          nodes: %{
            any() => Node.t()
          },
          starting_node_id: any(),
          outputs: keyword() | nil,
          max_retries: non_neg_integer()
        }

  @enforce_keys [:id, :nodes, :starting_node_id]
  defstruct [:id, :description, :nodes, :starting_node_id, :outputs, max_retries: 3]

  @spec from_json(binary()) :: t()
  def from_json(json) when is_binary(json) do
    json |> Jason.decode!() |> from_map()
  end

  @spec from_map(map()) :: t()
  def from_map(%{} = m) do
    nodes = Map.new(m["nodes"] || %{}, fn {k, v} -> {k, Node.from_map(v)} end)

    %__MODULE__{
      id: m["id"],
      description: m["description"],
      nodes: nodes,
      starting_node_id: m["starting_node_id"],
      outputs: m["outputs"],
      max_retries: m["max_retries"] || 3
    }
  end
end
