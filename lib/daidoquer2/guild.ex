defmodule Daidoquer2.Guild do
  use GenServer, restart: :transient

  require Logger

  alias Daidoquer2.DiscordAPI, as: D
  alias Daidoquer2.GuildDiscordEventHandler, as: H
  alias Daidoquer2.GuildSpeaker, as: S
  alias Daidoquer2.CancellableTimer, as: T

  #####
  # External API

  def name(guild_id) do
    {:via, Registry, {Registry.Guild, guild_id}}
  end

  def start_link(guild_id) do
    GenServer.start_link(__MODULE__, guild_id, name: name(guild_id))
  end

  def join_channel(pid, msg) do
    GenServer.cast(pid, {:join, {:message, msg}})
  end

  def join_channel_via_interaction(pid, interaction) do
    GenServer.cast(pid, {:join, {:interaction, interaction}})
  end

  def leave_channel(pid, msg) do
    GenServer.cast(pid, {:leave, {:message, msg}})
  end

  def leave_channel_via_interaction(pid, interaction) do
    GenServer.cast(pid, {:leave, {:interaction, interaction}})
  end

  def notify_voice_state_updated(pid, voice_state) do
    Logger.debug("VOICE_STATE_UPDATE: #{inspect(voice_state)}")
    GenServer.cast(pid, {:voice_state_updated, voice_state})
  end

  def notify_voice_ready(pid, state) do
    Logger.debug("VOICE_READY: #{inspect(state)}")
    GenServer.cast(pid, :voice_ready)
  end

  def thread_create(pid, channel) do
    Logger.debug("THREAD_CREATE: #{inspect(channel)}")
    GenServer.cast(pid, {:thread_create, channel})
  end

  #####
  # GenServer callbacks

  def init(guild_id) do
    state = %{
      guild_id: guild_id,
      voice_states: %{},
      speaker: S.name(guild_id)
    }

    voice_connected = D.voice(guild_id) != nil
    is_in_vc = D.voice_channel_of_user!(guild_id, D.me().id) != nil

    Logger.debug(
      "INIT: Voice status (#{guild_id}): voice_connected=#{voice_connected}: is_in_vc=#{is_in_vc}"
    )

    S.cast_reset_state(state.speaker)

    cond do
      !is_in_vc && !voice_connected ->
        {:ok, state}

      is_in_vc && voice_connected ->
        reset_leave_timer(guild_id)
        state = %{state | voice_states: get_voice_states(guild_id)}
        {:ok, state}

      (is_in_vc && !voice_connected) || (!is_in_vc && voice_connected) ->
        # Invalid state
        Supervisor.stop(Daidoquer2.GuildSup.name(guild_id))
        {:stop, :normal}
    end
  end

  def handle_cast({:thread_create, channel}, state) do
    thread_name = channel.name
    user_name = D.display_name_of_user!(state.guild_id, channel.owner_id)
    H.thread_create(thread_name, user_name, state)
    {:noreply, state}
  end

  def handle_cast({:voice_state_updated, voice_state}, state) do
    true = voice_state.guild_id == state.guild_id

    p = state.voice_states |> Map.get(voice_state.user_id)
    c = voice_state
    my_user_id = D.me().id
    ch = D.voice_channel_of_user!(state.guild_id, my_user_id)

    joining_any_channel = c.channel_id != nil and (p == nil or p.channel_id != c.channel_id)
    joining = joining_any_channel and c.channel_id == ch
    leaving = p != nil and ch != nil and p.channel_id != c.channel_id and p.channel_id == ch
    about_me = voice_state.user_id == my_user_id
    my_joining = about_me and joining
    my_leaving = about_me and (leaving or ch == nil)

    start_streaming =
      c.channel_id == ch and p != nil and
        (not Map.has_key?(p, :self_stream) or not p.self_stream) and
        (Map.has_key?(c, :self_stream) and c.self_stream)

    stop_streaming =
      c.channel_id == ch and p != nil and
        (Map.has_key?(p, :self_stream) and p.self_stream) and
        (not Map.has_key?(c, :self_stream) or not c.self_stream)

    new_state = %{
      state
      | voice_states: Map.put(state.voice_states, voice_state.user_id, voice_state)
    }

    cond do
      my_joining ->
        H.i_join(new_state)
        reset_leave_timer(new_state.guild_id)
        {:noreply, new_state}

      my_leaving ->
        H.i_leave(new_state)
        S.cast_reset_state(new_state.speaker)
        {:noreply, new_state}

      joining ->
        H.someone_join(voice_state.user_id, new_state)
        reset_leave_timer(new_state.guild_id)
        {:noreply, new_state}

      leaving ->
        H.someone_leave(voice_state.user_id, new_state)
        reset_leave_timer(new_state.guild_id)
        {:noreply, new_state}

      start_streaming ->
        H.start_streaming(voice_state.user_id, new_state)
        {:noreply, new_state}

      stop_streaming ->
        H.stop_streaming(voice_state.user_id, new_state)
        {:noreply, new_state}

      joining_any_channel ->
        set_join_timer(c.channel_id)
        {:noreply, new_state}

      true ->
        {:noreply, new_state}
    end
  end

  def handle_cast({:join, msg}, state) do
    {guild_id, uid} =
      case msg do
        {:message, msg} -> {msg.guild_id, msg.author.id}
        {:interaction, intr} -> {intr.guild_id, intr.user.id}
      end

    true = guild_id == state.guild_id
    voice_channel_id = D.voice_channel_of_user!(state.guild_id, uid)
    new_state = %{state | voice_states: get_voice_states(guild_id)}

    cond do
      voice_channel_id == nil ->
        H.summon_not_from_vc(msg, new_state)
        {:noreply, new_state}

      voice_channel_id == D.voice_channel_of_user!(state.guild_id, D.me().id) ->
        H.summon_but_already_joined(msg, new_state)
        {:noreply, new_state}

      true ->
        H.summon(msg, voice_channel_id, new_state)
        {:noreply, new_state}
    end
  end

  def handle_cast({:leave, msg}, state) do
    {guild_id, uid} =
      case msg do
        {:message, msg} -> {msg.guild_id, msg.author.id}
        {:interaction, intr} -> {intr.guild_id, intr.user.id}
      end

    true = guild_id == state.guild_id
    voice_ready = D.voice_ready?(state.guild_id)
    user_vc_id = D.voice_channel_of_user!(state.guild_id, uid)
    my_vc_id = D.voice_channel_of_user!(state.guild_id, D.me().id)

    cond do
      not voice_ready ->
        H.unsummon_not_joined(msg, state)

      user_vc_id != my_vc_id ->
        H.unsummon_not_from_same_vc(msg, state)

      true ->
        H.unsummon(msg, state)
    end

    {:noreply, state}
  end

  def handle_cast(:voice_ready, state) do
    S.notify_voice_ready(state.speaker)
    {:noreply, state}
  end

  def handle_info({:timeout, arg}, state) do
    T.dispatch(arg, state, __MODULE__)
  end

  def handle_timeout({:join, vc_id}, state) do
    # Join the channel now, if:
    # - I've not yet joined a channel and
    # - Someone is still in the channel
    not_yet_joined = D.voice_channel_of_user!(state.guild_id, D.me().id) == nil
    someone_in = D.num_of_users_in_channel!(state.guild_id, vc_id) != 0

    if not_yet_joined and someone_in do
      Logger.debug("Joining #{state.guild_id}: #{vc_id}")
      S.join_channel(state.speaker, vc_id)
    end

    {:noreply, state}
  end

  def handle_timeout(:leave, state) do
    # Leave the channel now
    Logger.debug("Leaving #{state.guild_id}")
    S.stop_speaking_and_clear_message_queue(state.speaker)
    S.schedule_leave(state.speaker)
    {:noreply, state}
  end

  #####
  # Internals

  defp set_join_timer(vc_id) do
    ms = Application.fetch_env!(:daidoquer2, :ms_before_join)

    if ms != 0 do
      T.set_timer({:join, vc_id}, ms)
    end
  end

  defp reset_leave_timer(guild_id) do
    case D.num_of_users_in_my_channel!(guild_id) do
      0 ->
        ms = Application.fetch_env!(:daidoquer2, :ms_before_leave)

        if ms != 0 do
          T.set_timer(:leave, ms)
        end

      _ ->
        T.cancel_timer(:leave)
    end
  end

  defp get_voice_states(guild_id) do
    guild_id
    |> D.guild!()
    |> Map.get(:voice_states)
    |> Map.new(fn s -> {s.user_id, s} end)
  end
end
