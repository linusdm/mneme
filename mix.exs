defmodule Mneme.MixProject do
  use Mix.Project

  @app :mneme
  @source_url "https://github.com/zachallaun/mneme"

  def version, do: "0.0.1"

  def project do
    [
      app: @app,
      version: version(),
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      aliases: aliases(),
      preferred_cli_env: preferred_cli_env(),

      # Hex
      description: "Semi-automated snapshot testing with ExUnit",
      package: package()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp aliases do
    [
      t: "coveralls"
    ]
  end

  defp preferred_cli_env do
    [
      t: :test
    ]
  end

  defp package do
    [
      name: "mneme",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp deps do
    [
      {:nimble_options, "~> 0.5.2"},
      {:sourceror, "~> 0.12"},
      {:rewrite, "~> 0.4.0"},
      {:dialyxir, "~> 1.2", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.15", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp elixirc_paths, do: elixirc_paths(Mix.env())
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix],
      flags: [
        :underspecs,
        :extra_return,
        :missing_return
      ]
    ]
  end
end
