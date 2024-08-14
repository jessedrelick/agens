defmodule Agens.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :agens,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Library for creating AI agents",
      package: package(),
      docs: docs()
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
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false},
      {:bumblebee, "~> 0.5.3"},
      {:exla, "~> 0.7.0"},
      {:meck, "~> 0.9.2", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      maintainers: ["Jesse Drelick"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jessedrelick/agens"}
    ]
  end

  defp docs do
    [
      main: "Agens",
      extras: ["README.md"],
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
end
