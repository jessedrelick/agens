defmodule Agens.Resource do
  @moduledoc """
  Represents a resource attached to an `Agens.Job.Node` and made available to a Serving prior to inference.

  A Resource pairs an external `:uri` with a human-readable `:name`/`:description` and optional inline `:content`.
  Resources are typically loaded by a Serving (see `c:Agens.Serving.load_resource/3`) and rendered into the
  LM prompt via `Agens.Prompt`.

  ## Fields

    * `:uri` - The identifier or location of the resource (e.g. a URL, file path, or MCP resource URI). Required.
    * `:name` - A short, human-readable name for the resource. Required.
    * `:description` - An optional description of the resource.
    * `:content` - Optional inline content for the resource, typically populated after `load_resource/3` resolves it.
  """

  @derive [Jason.Encoder]

  @type t :: %__MODULE__{
          uri: String.t(),
          name: String.t(),
          description: String.t() | nil,
          content: String.t() | nil
        }

  @enforce_keys [:uri, :name]
  defstruct [:uri, :name, :description, :content]

  @doc """
  Builds an `Agens.Resource` from a decoded map (e.g. the output of `Jason.decode!/1`).

  String keys are expected.
  """
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
