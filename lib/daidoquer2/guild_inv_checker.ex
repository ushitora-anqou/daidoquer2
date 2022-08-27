defmodule Daidoquer2.GuildInvChecker do
  use GenServer, restart: :transient

  require Logger

  alias Daidoquer2.DiscordAPI, as: D
  alias Daidoquer2.GuildSpeaker, as: S
  alias Daidoquer2.CancellableTimer, as: T

  @interval_for_checking_invariant 60 * 1000
  @max_retries_for_check_invariant 3

  #####
  # External API

  def name(guild_id) do
    {:via, Registry, {Registry.InvChecker, guild_id}}
  end

  def start_link(guild_id) do
    GenServer.start_link(__MODULE__, guild_id, name: name(guild_id))
  end

  #####
  # GenServer callbacks

  def init(guild_id) do
    set_check_invariant_timer()

    {:ok,
     %{
       guild_id: guild_id,
       fail_counter: 0
     }}
  end

  def handle_info({:timeout, arg}, state) do
    T.dispatch(arg, state, __MODULE__)
  end

  def handle_timeout(:check_invariant, state) do
    # Check everything is ok.
    # NOTE: This check is intented to be used when Nostrum's WebSocket connection is quietly broken.
    guild_id = state.guild_id
    voice_connected = D.voice(guild_id) != nil
    is_in_vc = D.voice_channel_of_user!(guild_id, D.me().id) != nil
    speaker_enabled = S.is_enabled(S.name(guild_id))

    result =
      cond do
        (voice_connected && !is_in_vc) || (!voice_connected && is_in_vc) ->
          # NOTE: unlikely
          {:error, :invalid_voice_state}

        (speaker_enabled && !voice_connected) || (!speaker_enabled && voice_connected) ->
          # NOTE: could be false positive
          {:error, :invalid_speaker_state}

        true ->
          :ok
      end

    case result do
      :ok ->
        set_check_invariant_timer()
        {:noreply, %{state | fail_counter: 0}}

      {:error, reason} ->
        Logger.warn("Invariant check failed: #{state.fail_counter}: #{inspect(reason)}")

        if state.fail_counter < @max_retries_for_check_invariant do
          set_check_invariant_timer(state.fail_counter + 1)
          {:noreply, %{state | fail_counter: state.fail_counter + 1}}
        else
          {:stop, reason, state}
        end
    end
  end

  #####
  # Internals

  defp set_check_invariant_timer(fail_counter \\ 0) do
    scale = :math.pow(2, fail_counter) |> round
    ms = (@interval_for_checking_invariant / scale) |> round
    T.set_timer(:check_invariant, ms)
  end
end
