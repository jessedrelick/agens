defmodule AgensDemo.Tools.Echo do
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  def name, do: "echo"
  def description, do: "Echoes a message back to the caller"

  schema do
    field :message, :string,
      required: true,
      description: "The message to echo"
  end

  @impl true
  def execute(%{message: message}, frame) do
    response =
      Response.tool()
      |> Response.text("Echo: " <> message)

    {:reply, response, frame}
  end
end
