defmodule ElixirFastCharge.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_fast_charge,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {ElixirFastCharge.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug_cowboy, "~> 2.0"},
      {:cors_plug, "~> 3.0"},
      {:plug, "~> 1.15"},
      {:jason, "~> 1.4"},
      {:horde, "~> 0.8.3"},
      {:libcluster, "~> 3.3"},
      {:telemetry, "~> 1.0"},
      {:telemetry_metrics_prometheus, "~> 1.1"},
      {:telemetry_poller, "~> 1.0"},
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
