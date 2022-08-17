defmodule Daidoquer2.GuildVoiceStateStore do
  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def get(guild_id) do
    case :ets.lookup(__MODULE__, guild_id) do
      [] -> %{}
      [{^guild_id, vstate}] -> vstate
    end
  end

  def put(guild_id, vstate) do
    GenServer.cast(__MODULE__, {:put, {guild_id, vstate}})
  end

  def reset(guild_id) do
    GenServer.cast(__MODULE__, {:reset, guild_id})
  end

  #####
  # External API

  @impl true
  def init(nil) do
    :ets.new(__MODULE__, [:set, :protected, :named_table])
    {:ok, nil}
  end

  @impl true
  def handle_cast({:put, {guild_id, vstate}}, _) do
    true = :ets.insert(__MODULE__, {guild_id, vstate})
    {:noreply, nil}
  end

  @impl true
  def handle_cast({:reset, guild_id}, _) do
    :ets.delete(__MODULE__, guild_id)
    {:noreply, nil}
  end
end
