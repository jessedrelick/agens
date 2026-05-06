defmodule AgensDemo.Resources.Agens do
  use Hermes.Server.Component, type: :resource

  alias Hermes.Server.Response

  def uri, do: "agens://resources/agens"
  def name, do: "agens"
  def description, do: "High-level overview of Agens: what it is, what it is used for, and how it works"
  def mime_type, do: "text/plain"

  @impl true
  def read(_params, frame) do
    response =
      Response.resource()
      |> Response.text("""
      # Agens

      Agens is a multi-agent orchestration framework written in Elixir. It enables complex LLM
      workflows by composing Agents, Jobs, Nodes, and Servings into coordinated pipelines.

      ## Core Concepts

      **Serving** — Wraps a language model (or any inference backend). Implements `handle_message/3`
      to call the LLM and `handle_result/3` to parse the response into an `Agens.Serving.Result`.

      **Agent** — A named participant in a workflow. Each Agent is bound to a Serving and carries
      optional configuration (identity, persona, etc).

      **Job** — Defines a multi-step workflow as a directed graph of Nodes. A Job is started with
      an input and runs until a Node returns `:end` or an error occurs.

      **Node** — A single step within a Job. Specifies which Agent handles it, an optional
      objective, and optional Tool and Resource definitions.

      **Message** — The unit of data flowing through the pipeline. Carries the input,
      system/user prompts, LLM result, outputs, tool calls/results, and routing instructions.

      ## MCP Integration

      Nodes can be configured with:
      - **Tools** — functions the LLM can invoke during execution (e.g. database queries, API calls).
      - **Resources** — read-only data injected into the prompt as context before the LLM is called.
      """)

    {:reply, response, frame}
  end
end

defmodule AgensDemo.Resources.BriefGuidelines do
  use Hermes.Server.Component, type: :resource

  alias Hermes.Server.Response

  def uri, do: "agens://resources/brief_guidelines"
  def name, do: "brief_guidelines"
  def description, do: "Structure and format guidelines for writing an industry brief"
  def mime_type, do: "text/plain"

  @impl true
  def read(_params, frame) do
    response =
      Response.resource()
      |> Response.text("""
      # Industry Brief Guidelines

      ## Purpose
      An industry brief provides a concise, authoritative overview of a topic for a professional
      audience. Target length: 500-800 words.

      ## Structure

      ### 1. Executive Summary (50-75 words)
      A high-level overview of the topic, its significance, and key takeaways.

      ### 2. Background & Context (100-150 words)
      Historical context, how the topic emerged, and why it matters today.

      ### 3. Current Landscape (150-200 words)
      Present state: key players, market dynamics, and major recent developments.

      ### 4. Key Trends & Drivers (100-150 words)
      The forces shaping the topic: technology, regulation, consumer behavior, macroeconomics.

      ### 5. Challenges & Risks (75-100 words)
      Primary obstacles, uncertainties, or risks practitioners should be aware of.

      ### 6. Outlook (75-100 words)
      Forward-looking perspective: where the topic is headed and what to watch for.

      ## Style Guidelines
      - Professional but accessible tone
      - Use specific data points and examples where available
      - Avoid unexplained jargon
      - Active voice preferred
      """)

    {:reply, response, frame}
  end
end
