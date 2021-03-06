defmodule Daidoquer2.MixProject do
  use Mix.Project

  def project do
    [
      app: :daidoquer2,
      version: "0.1.12",
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :porcelain],
      mod: {Daidoquer2.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      # {:nostrum, "~> 0.4"},
      {:nostrum, git: "https://github.com/ushitora-anqou/nostrum.git", override: true},
      {:httpoison, "~> 1.8.0"},
      {:temp, "~> 0.4"},
      {:gproc, "~> 0.8.0"},
      {:mbcs_rs, "~> 0.1"},
      {:emojix, "~> 0.3"},
      {:distillery, "~> 2.0"}
    ]
  end
end
