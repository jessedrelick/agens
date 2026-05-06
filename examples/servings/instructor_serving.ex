defmodule AgensDemo.InstructorServing do
  use Agens.Serving

  alias Agens.{Message, Serving}

  @agents_dir Path.expand("../agents", __DIR__)

  @impl Serving
  def start(state), do: {:ok, state}

  @impl Serving
  def outputs_schema(%Message{} = message) do
    props = AgensRouter.Output.to_json_schema(AgensDemo.AgensRouter.outputs(message))

    {"outputs",
     %{
       "type" => "object",
       "additionalProperties" => false,
       "properties" => props,
       "required" => Map.keys(props)
     }}
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
  def handle_message(state, %Message{system: system, user: user}, schema) do
    source = Keyword.get(state.config.args, :source, :openai)
    model = Keyword.get(state.config.args, :model)
    AgensDemo.InstructorParams.call(source, model, system, user, schema)
  end

  @impl Serving
  def handle_result({:ok, _response, %{"body" => body} = parsed}, _state, message) do
    outputs = Map.get(parsed, "outputs", %{})
    next = AgensDemo.AgensRouter.route(%{message | outputs: outputs})
    {:ok, %Serving.Result{body: body, outputs: outputs, next: next}}
  end

  def handle_result({:error, reason}, _state, _message), do: {:error, reason}
end
