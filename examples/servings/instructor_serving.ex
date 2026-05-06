defmodule AgensDemo.InstructorServing do
  use Agens.Serving

  alias Agens.{Message, Serving}
  alias Instructor.Adapters

  @agents_dir Path.expand("../agents", __DIR__)

  @adapters %{
    openai: Adapters.OpenAI,
    anthropic: Adapters.Anthropic,
    gemini: Adapters.Gemini,
    groq: Adapters.Groq,
    ollama: Adapters.Ollama
  }

  @default_models %{
    openai: "gpt-4o-mini",
    anthropic: "claude-haiku-4-5-20251001",
    gemini: "gemini-1.5-flash",
    groq: "llama-3.1-8b-instant",
    ollama: "llama3.2"
  }

  # Uses response_format / json_schema structured output
  @json_schema_providers [:openai, :gemini]

  # Uses tool_choice to enforce structured output
  @tools_providers [:anthropic, :groq, :ollama]

  @response_schema %{
    "type" => "object",
    "required" => ["body"],
    "additionalProperties" => false,
    "properties" => %{
      "body" => %{"type" => "string", "description" => "Your response"}
    }
  }

  @impl Serving
  def start(state) do
    {:ok, state}
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
  def handle_message(state, %Message{system: system, user: user}, _schema) do
    source = Keyword.get(state.config.args, :source, :openai)
    model = Keyword.get(state.config.args, :model, Map.get(@default_models, source, "gpt-4o-mini"))

    source
    |> build_params(model, system, user)
    |> adapter!(source).chat_completion()
  end

  @impl Serving
  def handle_result({:ok, _response, %{"body" => body}}, state, message) do
    next = route(state.config.args, message)
    {:ok, %Serving.Result{body: body, next: next}}
  end

  def handle_result({:error, reason}, _state, _message) do
    {:error, reason}
  end

  # ===========================================================================
  # Params builders
  # ===========================================================================

  defp build_params(source, model, system, user) when source in @json_schema_providers do
    [
      mode: :json_schema,
      model: model,
      response_format: %{
        type: "json_schema",
        json_schema: %{name: "agens_response", schema: @response_schema, strict: true}
      },
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user}
      ]
    ]
  end

  defp build_params(source, model, system, user) when source in @tools_providers do
    [
      mode: :tools,
      model: model,
      max_tokens: 2048,
      tools: [
        %{
          function: %{
            "name" => "agens_response",
            "description" => "Your response",
            "parameters" => @response_schema
          }
        }
      ],
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user}
      ]
    ]
  end

  # ===========================================================================
  # Helpers
  # ===========================================================================

  defp adapter!(source) do
    case Map.fetch(@adapters, source) do
      {:ok, adapter} -> adapter
      :error -> raise ArgumentError, "unsupported provider: #{inspect(source)}"
    end
  end

  defp route(args, message) do
    case Keyword.get(args, :router) do
      nil -> [:end]
      router -> router.(message)
    end
  end
end
