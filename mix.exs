defmodule Agens.MixProject do
  use Mix.Project

  @version "0.2.0"

  def project do
    [
      app: :agens,
      version: @version,
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Multi-agent workflows with language models on OTP — dynamic routing, MCP-shaped tools and resources, structured outputs, and pluggable observability.",
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coverage: :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:jason, "~> 1.4"},
      {:telemetry_metrics, "~> 1.0"},
      {:dialyxir, "~> 1.4.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:excoveralls, "~> 0.17.1", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Jesse Drelick"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/jessedrelick/agens"},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md),
      build_tools: ["mix"],
      keywords: [
        "AI",
        "Agents",
        "AI Agents",
        "Multi-Agent Systems",
        "LLM",
        "Language Models",
        "MCP",
        "Routing",
        "Structured Outputs",
        "Task Orchestration",
        "Workflow Automation"
      ],
      categories: [
        "Machine Learning",
        "Artificial Intelligence",
        "Automation"
      ]
    ]
  end

  defp docs do
    [
      main: "Agens",
      extras: [
        {"README.md", [title: "Agens"]},
        {"docs/design-philosophy.md", [title: "Design Philosophy"]},
        {"docs/host-responsibilities.md", [title: "Host Application Responsibilities"]},
        {"CHANGELOG.md", [title: "Changelog"]},
        "LICENSE"
      ],
      source_url: "https://github.com/jessedrelick/agens",
      groups_for_modules: [
        Job: [
          Agens.Job,
          Agens.Job.Config,
          Agens.Job.Node,
          Agens.Job.Sub
        ],
        Router: [
          Agens.Router,
          Agens.Router.Condition,
          Agens.Router.Output
        ],
        Serving: [
          Agens.Serving,
          Agens.Serving.Config,
          Agens.Serving.Result
        ],
        Misc: [
          Agens.Backend,
          Agens.Metrics,
          Agens.Prefixes,
          Agens.Prompt,
          Agens.Resource,
          Agens.Schema,
          Agens.Supervisor
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp aliases do
    [
      "test.all": ["test --include lm"],
      "test.lm": ["test --only lm"]
    ]
  end
end
