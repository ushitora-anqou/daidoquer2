defmodule Daidoquer2.GuildSup do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg)
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
      {Daidoquer2.Guild, {self(), guild_id}}
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end
end
