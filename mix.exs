defmodule Mix.Tasks.Compile.CSource do
  def run(_args) do
    {result, errcode} = System.cmd("make", [])

    if errcode == 0 do
      IO.binwrite(result)
    else
      {:error, [{:make_fail, result, errcode}]}
    end
  end
end

defmodule Daidoquer2.MixProject do
  use Mix.Project

  def project do
    [
      app: :daidoquer2,
      version: "0.5.12",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        daidoquer2: [
          steps: [:assemble, :tar]
        ]
      ],
      compilers: [:c_source] ++ Mix.compilers()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Daidoquer2.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
      {:nostrum, "~> 0.9.0-alpha2"},
      {:httpoison, "~> 2.1.0"},
      {:temp, "~> 0.4"},
      # {:emojix, "~> 0.3"},
      {:emojix, git: "https://github.com/ushitora-anqou/emojix.git"},
      {:google_api_text_to_speech, "~> 0.15"},
      {:goth, "~> 1.4.1"},
      {:erlexec, "~> 2.0"}
    ]
  end
end
