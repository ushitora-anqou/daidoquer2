defmodule Daidoquer2.GuildKiller do
  use GenServer

  require Logger

  @seconds_to_wait 10 * 60 * 1000

  #####
  # External API

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def set_timer(guild_id) do
    GenServer.cast(__MODULE__, {:set_timer, guild_id})
  end

  def cancel_timer(guild_id) do
    GenServer.cast(__MODULE__, {:cancel_timer, guild_id})
  end

  #####
  # GenServer callbacks

  def init(_) do
    {:ok, %{}}
  end

  def handle_cast({:set_timer, guild_id}, state) do
    ref = make_ref()
    Process.send_after(self(), {:timeout, ref, guild_id}, @seconds_to_wait)
    Logger.debug("Setting kill timer for #{guild_id}")
    {:noreply, Map.put(state, guild_id, ref)}
  end

  def handle_cast({:cancel_timer, guild_id}, state) do
    Logger.debug("Cancelling kill timer for #{guild_id}")
    {:noreply, Map.delete(state, guild_id)}
  end

  def handle_info({:timeout, ref, guild_id}, state) do
    {_, new_state} =
      state
      |> Map.get_and_update(guild_id, fn
        ^ref ->
          # The guild should be killed.
          Daidoquer2.GuildRegistry.cast_if_exists(guild_id, :leave_channel)
          :pop

        _ ->
          :pop
      end)

    {:noreply, new_state}
  end
end
