defmodule Agens.Job.Node do
  @moduledoc """
  The Node struct defines a single node within a Job.

  ## Fields
  - `agent_id` - The identifier of the agent to be used in the Node.
  - `objective` - An optional string to be added to the LM prompt explaining the purpose of the Node.
  """

  @derive [Jason.Encoder]

  @type schema :: binary()

  @type t :: %__MODULE__{
          serving: atom(),
          agent_id: any() | nil,
          sub: binary() | nil,
          next: list() | nil,
          objective: String.t() | nil,
          tools: list(schema()) | nil,
          resources: list(Agens.Resource.t()) | nil
        }

  @enforce_keys []
  defstruct [:serving, :agent_id, :sub, :next, :objective, :tools, :resources]

  @spec from_map(map()) :: t()
  def from_map(%{} = m) do
    %__MODULE__{
      serving: m["serving"] && String.to_existing_atom(m["serving"]),
      agent_id: m["agent_id"],
      sub: m["sub"],
      next: m["next"],
      objective: m["objective"],
      tools: m["tools"],
      resources: m["resources"] && Enum.map(m["resources"], &Agens.Resource.from_map/1)
    }
  end
end
