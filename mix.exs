defmodule Agens.MixProject do
  use Mix.Project

  def project do
    [
      app: :agens,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "Library for creating AI agents",
      package: package()
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
      {:hammox, "~> 0.7", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Jesse Drelick"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/jessedrelick/agens"}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]
end
