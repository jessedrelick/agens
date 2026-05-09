defmodule AgensDemo.InstructorServing do
  use Agens.Serving

  alias Agens.{Message, Serving}

  @source :ollama
  @model "qwen3:8b"
  # `qwen3:8b` for better performance
  # `gemma4:26b` for better results
  @router AgensDemo.EdgeRouter
  @agents_dir Path.expand("../agents", __DIR__)

  @impl Serving
  def start(state) do
    args = [source: @source, model: @model]

    {:ok, %{state | config: %{state.config | args: args}}}
  end

  @impl Serving
  def outputs_schema(%Message{} = message) do
    props =
      message
      |> @router.outputs()
      |> Agens.Router.Output.to_json_schema()

    {"outputs",
     %{
       "type" => "object",
       "additionalProperties" => false,
       "properties" => props,
       "required" => Map.keys(props)
     }}
  end

  @impl Serving
  def tools_schema(%Message{tool_defs: tool_defs}) do
    schema = Agens.Schema.tools()

    with names when is_list(names) and names != [] <- tool_defs,
         {:ok, %{"tools" => mcp_tools}} <- AgensDemo.MCPClient.list_tools() do
      available = MapSet.new(mcp_tools, & &1["name"])
      valid_names = Enum.filter(names, &MapSet.member?(available, &1))
      items = put_in(schema["items"]["properties"]["name"]["enum"], valid_names)
      {"tool_calls", %{schema | "items" => items}}
    else
      _ -> {"tool_calls", schema}
    end
  end

  @impl Serving
  def load_context(_state, %Message{agent_id: agent_id}) when is_binary(agent_id) do
    path = Path.join(@agents_dir, "#{agent_id}.md")

    case File.read(path) do
      {:ok, content} -> String.trim(content)
      {:error, _} -> nil
    end
  end

  def load_context(_state, _message), do: nil

  @impl Serving
  def load_resource(_state, %Agens.Resource{uri: uri} = resource, _message) do
    case AgensDemo.MCPClient.read_resource(uri) do
      {:ok, %{"contents" => [%{"text" => content} | _]}} -> %{resource | content: content}
      _ -> resource
    end
  end

  @impl Serving
  def handle_message(state, %Message{system: system, user: user, run_id: run_id}, schema) do
    source = Keyword.get(state.config.args, :source, :openai)
    model = Keyword.get(state.config.args, :model)
    history = if is_nil(run_id), do: [], else: AgensDemo.History.load(run_id)
    AgensDemo.InstructorParams.call(source, model, system, user, history, schema)
  end

  @impl Serving
  def tool_call(_state, %{"id" => id, "name" => name, "arguments" => args}, _message) do
    input = Map.new(args, fn %{"key" => k, "value" => v} -> {k, v} end)

    result =
      case AgensDemo.MCPClient.call_tool(name, input) do
        {:ok, %{"content" => [%{"text" => text} | _]}} -> text
        {:ok, result} -> inspect(result)
        {:error, reason} -> "Error: #{inspect(reason)}"
      end

    {id, result}
  end

  @impl Serving
  def handle_result({:ok, _response, %{"body" => body} = parsed}, _state, message) do
    outputs = Map.get(parsed, "outputs", %{})
    tool_calls = Map.get(parsed, "tool_calls", [])
    next = @router.route(%{message | outputs: outputs})
    {:ok, %Serving.Result{body: body, outputs: outputs, tool_calls: tool_calls, next: next}}
  end

  def handle_result({:error, reason}, _state, _message), do: {:error, reason}
end
