defmodule Test.Support.Tools.NoopTool do
  @behaviour Agens.Tool

  @impl true
  def pre(input), do: input

  @impl true
  def instructions(), do: ""

  @impl true
  def to_args(_input), do: []

  @impl true
  def execute(_args), do: %{}

  @impl true
  def post(_result), do: "TRUE"
end
