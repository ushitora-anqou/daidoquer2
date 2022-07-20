defmodule Daidoquer2.GuildTimer do
  use GenServer

  require Logger

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

  def handle_info({:timeout, ref, guild_id, key}, state) do
    {_, new_state} =
      state
      |> Map.get_and_update({guild_id, key}, fn
        ^ref ->
          Logger.debug("Timeout: #{guild_id}: #{inspect(key)}: #{inspect(ref)}")
          Daidoquer2.Guild.cast_timeout({:via, Registry, {Registry.Guild, guild_id}}, key)
          :pop

        current_ref ->
          Logger.debug(
            "GuildKiller skip: #{guild_id}: #{inspect(key)}: #{inspect(ref)}: #{inspect(current_ref)}"
          )

          {current_ref, current_ref}
      end)

    {:noreply, new_state}
  end
end
