defmodule Sourceror.MixProject do
  use Mix.Project

  @version "0.5.0"
  @repo_url "https://github.com/doorgan/sourceror"

  def project do
    [
      app: :sourceror,
      name: "Sourceror",
      description: description(),
      version: @version,
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      package: package(),
      dialyzer: dialyzer(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:dev), do: ["lib"]
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp dialyzer do
    [
      plt_add_apps: [:mix, :erts, :kernel, :stdlib],
      flags: ["-Wunmatched_returns", "-Werror_handling", "-Wrace_conditions", "-Wno_opaque"],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      ignore_warnings: ".dialyzer_ignore.exs"
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev], runtime: false},
      {:ex_check, "~> 0.14.0", only: [:dev], runtime: false},
      {:ex_doc, "~> 0.24.2", only: :dev, runtime: false},
      {:excoveralls, "~> 0.10", only: [:test]},
      {:sobelow, "~> 0.8", only: :dev}
    ]
  end

  defp description do
    "Utilities to work with Elixir source code."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @repo_url
      }
    ]
  end

  defp docs do
    [
      main: "Sourceror",
      source_ref: @version,
      source_url: @repo_url,
      homepage_url: @repo_url,
      extras: ["README.md"]
    ]
  end
end
