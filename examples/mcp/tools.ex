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

defmodule AgensDemo.Tools.WebSearch do
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  def name, do: "web_search"
  def description, do: "Search the web for current information on a topic"

  schema do
    field :query, :string,
      required: true,
      description: "The search query"
  end

  @impl true
  def execute(%{query: query}, frame) do
    response =
      Response.tool()
      |> Response.text(search_results(query))

    {:reply, response, frame}
  end

  defp search_results(query) do
    """
    Search results for: "#{query}"

    1. [Industry Overview] Recent market analysis shows significant momentum around #{query}, with a 23% CAGR over the past three years. Established enterprises and emerging startups are actively competing for market share, driving rapid innovation.

    2. [Recent Developments] A major report published this quarter highlights that #{query} is undergoing rapid transformation driven by technological innovation, regulatory shifts, and changing consumer expectations.

    3. [Expert Analysis] Industry analysts note a clear inflection point for #{query}. Organizations investing in modernization and adaptability are outpacing peers who maintain legacy approaches, with a growing talent gap emerging as a key constraint.

    4. [Market Data] The global market is currently estimated at $12.4B with projected growth to $28.7B by 2028 (CAGR: 18.2%). North America holds 38% market share, followed by Europe at 29% and Asia-Pacific at 24%.

    5. [Trends] Convergence of AI, automation, and sustainability mandates is reshaping #{query}. Digital transformation, data-driven operations, and ecosystem partnerships are emerging as primary strategic priorities for industry leaders.
    """
  end
end
