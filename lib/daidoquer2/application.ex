defmodule Daidoquer2.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Starts a worker by calling: Daidoquer2.Worker.start_link(arg)
      # {Daidoquer2.Worker, arg}
      Daidoquer2.DiscordEventConsumer,
      Daidoquer2.GuildRegistry,
      Daidoquer2.GuildSupervisor,
      Daidoquer2.GuildKiller
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Daidoquer2.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
