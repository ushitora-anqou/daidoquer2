defmodule Daidoquer2.GuildSupervisor do
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_speaker(guild_id) do
    DynamicSupervisor.start_child(__MODULE__, {Daidoquer2.GuildSpeaker, guild_id})
  end

  def add_guild(guild_id) do
    DynamicSupervisor.start_child(__MODULE__, {Daidoquer2.Guild, guild_id})
  end
end
