defmodule Daidoquer2.GuildSupSup do
  use DynamicSupervisor

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :temporary
    }
  end

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one, max_seconds: 60)
  end

  def add_guild(guild_id) do
    DynamicSupervisor.start_child(__MODULE__, {Daidoquer2.GuildSup, guild_id})
  end
end
