defmodule AgensDemo.InstructorParams do
  alias Instructor.Adapters

  @adapters %{
    openai: Adapters.OpenAI,
    anthropic: Adapters.Anthropic,
    gemini: Adapters.Gemini,
    groq: Adapters.Groq
  }

  @default_models %{
    openai: "gpt-4o-mini",
    anthropic: "claude-haiku-4-5-20251001",
    gemini: "gemini-1.5-flash",
    groq: "llama-3.1-8b-instant"
  }

  @json_schema_providers [:openai, :gemini]
  @tools_providers [:anthropic, :groq]

  def call(source, model, system, user, history \\ [], schema) do
    model = model || Map.get(@default_models, source, "gpt-4o-mini")

    source
    |> build(model, system, user, history, schema)
    |> adapter!(source).chat_completion()
  end

  defp build(source, model, system, user, history, schema) when source in @json_schema_providers do
    [
      mode: :json_schema,
      model: model,
      response_format: %{
        type: "json_schema",
        json_schema: %{name: "agens_response", schema: schema, strict: true}
      },
      messages: base_messages(system, user, history)
    ]
  end

  defp build(source, model, system, user, history, schema) when source in @tools_providers do
    [
      mode: :tools,
      model: model,
      max_tokens: 2048,
      tools: [
        %{
          function: %{
            "name" => "agens_response",
            "description" => "Your response",
            "parameters" => schema
          }
        }
      ],
      messages: base_messages(system, user, history)
    ]
  end

  defp base_messages(system, user, history) do
    assistant = Enum.map(history, fn %{node_id: node_id, result: result} ->
      %{role: "assistant", content: "[#{node_id}]: #{result}"}
    end)

    [[%{role: "system", content: system}, %{role: "user", content: user}], assistant]
    |> Enum.concat()
  end

  defp adapter!(source) do
    case Map.fetch(@adapters, source) do
      {:ok, adapter} -> adapter
      :error -> raise ArgumentError, "unsupported provider: #{inspect(source)}"
    end
  end
end
