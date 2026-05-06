defmodule Agens.Resource do
  @derive [Jason.Encoder]

  @type t :: %__MODULE__{
          uri: String.t(),
          name: String.t(),
          description: String.t() | nil,
          content: String.t() | nil
        }

  @enforce_keys [:uri, :name]
  defstruct [:uri, :name, :description, :content]

  @spec from_map(map()) :: t()
  def from_map(%{} = m) do
    %__MODULE__{
      uri: m["uri"],
      name: m["name"],
      description: m["description"],
      content: m["content"]
    }
  end
end
