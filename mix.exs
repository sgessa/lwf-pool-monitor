defmodule LWF.MixProject do
  use Mix.Project

  def project do
    [
      app: :lwf,
      version: "0.1.2",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LWF.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:distillery, "~> 1.5", runtime: false},
      {:httpoison, "~> 1.0"},
      {:jason, "~> 1.0"},
      {:dpos, "~> 0.2.1"}
    ]
  end
end
