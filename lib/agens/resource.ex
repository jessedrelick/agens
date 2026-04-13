defmodule Agens.Resource do
  @type t :: %__MODULE__{
          uri: String.t(),
          name: String.t(),
          description: String.t() | nil,
          content: String.t() | nil
        }

  @enforce_keys [:uri, :name]
  defstruct [:uri, :name, :description, :content]
end
