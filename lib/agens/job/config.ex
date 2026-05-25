defmodule Agens.Job.Config do
  @moduledoc """
  The Config struct defines the static shape of a Job.

  ## Fields

    * `:id` - The unique identifier of the Job.
    * `:description` - An optional string added to the LM prompt that describes the goal of the Job.
    * `:nodes` - A map of `node_id => Agens.Job.Node` defining the workflow nodes.
    * `:starting_node_id` - The id of the Node that runs first when the Job is started.
    * `:outputs` - Optional output specification used when extracting structured data from the final Serving result.
    * `:max_retries` - Maximum retry attempts per Node before the Job errors out. Defaults to `3`.
  """

  alias Agens.Job.Node

  @derive [Jason.Encoder]

  @type t :: %__MODULE__{
          id: binary(),
          description: String.t() | nil,
          nodes: %{
            binary() => Node.t()
          },
          starting_node_id: binary(),
          outputs: keyword() | nil,
          max_retries: non_neg_integer()
        }

  @enforce_keys [:id, :nodes, :starting_node_id]
  defstruct [:id, :description, :nodes, :starting_node_id, :outputs, max_retries: 3]

  @doc """
  Builds a `Agens.Job.Config` from a JSON string.

  Delegates to `from_map/1` after decoding with `Jason`.
  """
  @spec from_json(binary()) :: t()
  def from_json(json) when is_binary(json) do
    json |> Jason.decode!() |> from_map()
  end

  @doc """
  Validates a `Agens.Job.Config`. Raises `ArgumentError` on the first invariant
  violation. Currently enforces that every Node declares a non-nil `:serving`.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{nodes: nodes} = config) do
    Enum.each(nodes, fn {node_id, node} ->
      if is_nil(node.serving) do
        raise ArgumentError,
              "Agens.Job.Node #{inspect(node_id)} is missing required field :serving"
      end
    end)

    config
  end

  @doc """
  Builds a `Agens.Job.Config` from a decoded map.

  String keys are expected. Each entry under `"nodes"` is converted via `Agens.Job.Node.from_map/1`.
  """
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
