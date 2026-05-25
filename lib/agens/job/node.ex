defmodule Agens.Job.Node do
  @moduledoc """
  The Node struct defines a single node within a Job.

  A Node is a combination of a text `:objective`, zero or more MCP `:tools` and `:resources`, an
  optional `:agent_id` for loading context, and an optional `:sub` Job to run in place of this
  Node's inference call. The `:serving` field is the only required link to a running process — it
  names the `Agens.Serving` that performs inference (or, when `:sub` is set, the Serving whose
  `c:Agens.Serving.handle_sub/3` callback maps the Sub-Job's result back into this Node's outputs
  and routing).

  ## Fields

    * `:serving` - The `Agens.Serving` to run inference against. Required, even when `:sub` is set; the Serving owns routing for the Node's result (via the Router's `outputs/1` + `resolve/2`, or via `handle_sub/3` when `:sub` is set).
    * `:agent_id` - The agent identifier used to load context for this Node (see `Serving.load_context/2`).
    * `:sub` - The id of a sub-Job to run in place of a Serving inference call. The Node's Serving is still used to route the Sub's result via `c:Agens.Serving.handle_sub/3`.
    * `:objective` - An optional string added to the LM prompt explaining the purpose of this Node.
    * `:tools` - Tool definitions made available to the Serving for this Node.
    * `:resources` - List of `Agens.Resource` structs to be loaded prior to inference.
  """

  @derive [Jason.Encoder]

  @typedoc "A tool schema, opaque to the Job."
  @type schema :: binary()

  @type t :: %__MODULE__{
          serving: atom(),
          agent_id: binary() | nil,
          sub: binary() | nil,
          objective: String.t() | nil,
          tools: list(schema()) | nil,
          resources: list(Agens.Resource.t()) | nil
        }

  @enforce_keys [:serving]
  defstruct [:serving, :agent_id, :sub, :objective, :tools, :resources]

  @doc """
  Builds a `Agens.Job.Node` from a decoded map (e.g. the output of `Jason.decode!/1`).

  String keys are expected. The `"serving"` field, if present, is converted to an existing atom.
  """
  @spec from_map(map()) :: t()
  def from_map(%{} = m) do
    %__MODULE__{
      serving: m["serving"] && String.to_existing_atom(m["serving"]),
      agent_id: m["agent_id"],
      sub: m["sub"],
      objective: m["objective"],
      tools: m["tools"],
      resources: m["resources"] && Enum.map(m["resources"], &Agens.Resource.from_map/1)
    }
  end
end
