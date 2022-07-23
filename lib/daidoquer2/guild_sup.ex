defmodule Daidoquer2.GuildSup do
  use Supervisor

  def name(guild_id) do
    {:via, Registry, {Registry.GuildSup, guild_id}}
  end

  def start_link(guild_id) do
    Supervisor.start_link(__MODULE__, guild_id, name: name(guild_id))
  end

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :transient
    }
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
