defmodule Agens.MixProject do
  use Mix.Project

  @version "0.1.1"

  def project do
    [
      app: :agens,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description:
        "Create multi-agent workflows with AI and Language Models using OTP components for reliable and scalable automation.",
      package: package(),
      docs: docs(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        "test.all": :test,
        "test.lm": :test,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:nx, "~> 0.7.3"},
      {:bumblebee, "~> 0.5.3", only: :test},
      {:exla, "~> 0.7.0", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:excoveralls, "~> 0.17.1", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Jesse Drelick"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => "https://github.com/jessedrelick/agens"},
      keywords: [
        "AI",
        "Agents",
        "AI Agents",
        "Multi-Agent Systems",
        "LLM",
        "Language Models",
        "NLP",
        "Task Orchestration",
        "Workflow Automation",
        "Bumblebee"
      ],
      categories: [
        "Machine Learning",
        "Artificial Intelligence",
        "Natural Language Processing",
        "Automation"
      ]
    ]
  end

  defp docs do
    [
      main: "Agens",
      extras: [{"README.md", [title: "Agens"]}, {"CHANGELOG.md", [title: "Changelog"]}, "LICENSE"],
      source_url: "https://github.com/jessedrelick/agens",
      groups_for_modules: [
        Agent: [
          Agens.Agent,
          Agens.Agent.Config,
          Agens.Agent.Prompt
        ],
        Job: [
          Agens.Job,
          Agens.Job.State,
          Agens.Job.Config,
          Agens.Job.Step
        ],
        Serving: [
          Agens.Serving,
          Agens.Serving.Config
        ],
        Tool: [
          Agens.Tool
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
