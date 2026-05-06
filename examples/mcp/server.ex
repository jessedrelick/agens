defmodule AgensDemo.MCPServer do
  use Hermes.Server,
    name: "AgensDemo MCP Server",
    version: "1.0.0",
    capabilities: [:tools, :resources]

  component(AgensDemo.Tools.Echo, type: :tool)
  component(AgensDemo.Resources.Agens, type: :resource)
end
