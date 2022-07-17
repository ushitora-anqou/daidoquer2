defmodule Daidoquer2.GuildSup do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg)
  end

  @impl true
  def init(guild_id) do
    children = [
      {Daidoquer2.GuildSpeaker, guild_id},
      {Daidoquer2.Guild, guild_id}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
