defmodule Daidoquer2.GuildTimer do
  use GenServer

  require Logger

  alias Daidoquer2.Guild, as: G

  #####
  # External API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def set_timer(guild_id, key, time) do
    GenServer.cast(__MODULE__, {:set_timer, guild_id, key, time})
  end

  def cancel_timer(guild_id, key) do
    GenServer.cast(__MODULE__, {:cancel_timer, guild_id, key})
  end

  def check_timeout({guild_id, key, ref}) do
    GenServer.call(__MODULE__, {:check_timeout, guild_id, key, ref})
  end

  #####
  # GenServer callbacks

  def init(_) do
    {:ok, %{}}
  end

  def handle_cast({:set_timer, guild_id, key, time}, state) do
    ref = make_ref()
    Process.send_after(self(), {:timeout, ref, guild_id, key}, time)
    Logger.debug("Setting timer: #{guild_id}: #{inspect(key)}: #{inspect(ref)}")
    {:noreply, Map.put(state, {guild_id, key}, ref)}
  end

  def handle_cast({:cancel_timer, guild_id, key}, state) do
    Logger.debug("Cancelling timer: #{guild_id}: #{inspect(key)}")
    {:noreply, Map.delete(state, {guild_id, key})}
  end

  def handle_call({:check_timeout, guild_id, key, ref}, _from, state) do
    case Map.fetch(state, {guild_id, key}) do
      {:ok, ^ref} ->
        Logger.debug("Check correct timeout: #{guild_id}: #{inspect(key)}: #{inspect(ref)}")
        {:reply, true, Map.delete(state, {guild_id, key})}

      _ ->
        Logger.debug("Check wrong timeout: #{guild_id}: #{inspect(key)}: #{inspect(ref)}")
        {:reply, false, state}
    end
  end

  def handle_info({:timeout, ref, guild_id, key}, state) do
    case Map.fetch(state, {guild_id, key}) do
      {:ok, _} ->
        Logger.debug("Timeout: #{guild_id}: #{inspect(key)}: #{inspect(ref)}")
        G.cast_timeout(G.name(guild_id), {key, {guild_id, key, ref}})

      :error ->
        Logger.debug("Cancelled timeout: #{guild_id}: #{inspect(key)}: #{inspect(ref)}")
    end

    {:noreply, state}
  end
end
