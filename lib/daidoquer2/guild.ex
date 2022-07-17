defmodule Daidoquer2.Guild do
  use GenServer, restart: :transient

  require Logger

  alias Daidoquer2.DiscordAPI, as: D
  alias Daidoquer2.GuildSpeaker, as: S

  #####
  # External API

  def start_link(guild_id) do
    name = {:via, Registry, {Registry.Guild, guild_id}}
    GenServer.start_link(__MODULE__, guild_id, name: name)
  end

  def join_channel(pid, msg) do
    GenServer.cast(pid, {:join, msg})
  end

  def kick_from_channel(pid) do
    GenServer.cast(pid, :kick)
  end

  def leave_channel(pid, msg) do
    GenServer.cast(pid, {:leave, msg})
  end

  def cast_message(pid, msg) do
    GenServer.cast(pid, {:discord_message, msg})
  end

  def cast_bare_message(pid, text) do
    GenServer.cast(pid, {:bare_message, text})
  end

  def notify_speaking_ended(pid) do
    GenServer.cast(pid, :speaking_ended)
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

  def get_num_users_in_channel(pid) do
    GenServer.call(pid, :num_users_in_channel)
  end

  #####
  # GenServer callbacks

  def init(guild_id) do
    GenServer.cast(self(), {:initialize_state, guild_id})
    {:ok, %{}}
  end

  def handle_cast({:initialize_state, guild_id}, _) do
    voice_connected = D.voice(guild_id) != nil
    is_in_vc = D.voice_channel_of_user!(guild_id, D.me().id) != nil

    Logger.debug(
      "INIT: Voice status (#{guild_id}): voice_connected=#{voice_connected}: is_in_vc=#{is_in_vc}"
    )

    state = %{
      guild_id: guild_id,
      voice_states: %{},
      num_users_in_channel: 0,
      speaker: {:via, Registry, {Registry.Speaker, guild_id}}
    }

    cond do
      !is_in_vc && !voice_connected ->
        {:noreply, state}

      is_in_vc && voice_connected ->
        num_users = D.num_of_users_in_my_channel!(guild_id)

        if num_users == 0 do
          Daidoquer2.GuildKiller.set_timer(guild_id)
        end

        {:noreply, %{state | num_users_in_channel: num_users}}

      (is_in_vc && !voice_connected) || (!is_in_vc && voice_connected) ->
        # Invalid state
        Supervisor.stop({:via, Registry, {Registry.GuildSup, guild_id}})
        {:stop, :normal, state}
    end
  end

  def handle_cast({:thread_create, channel}, state) do
    thread_name = channel.name
    user_name = D.display_name_of_user!(state.guild_id, channel.owner_id)

    Logger.debug("Thread created (#{state.guild_id}) #{thread_name} by #{user_name}")
    S.cast_bare_message(state.speaker, "#{user_name}さんがスレッド「#{thread_name}」を作りました。")

    {:noreply, state}
  end

  def handle_cast({:voice_state_updated, voice_state}, state) do
    true = voice_state.guild_id == state.guild_id

    {joining, leaving, my_joining, my_leaving, start_streaming, stop_streaming} =
      with p <- state.voice_states |> Map.get(voice_state.user_id),
           c <- voice_state,
           my_user_id <- D.me().id,
           ch <- D.voice_channel_of_user!(state.guild_id, my_user_id) do
        joining =
          if p == nil do
            ch != nil and c.channel_id == ch
          else
            ch != nil and p.channel_id != c.channel_id and c.channel_id == ch
          end

        leaving = p != nil and ch != nil and p.channel_id != c.channel_id and p.channel_id == ch
        about_me = voice_state.user_id == my_user_id
        my_joining = about_me and joining
        my_leaving = about_me and (leaving or ch == nil)

        start_streaming =
          p != nil and (not Map.has_key?(p, :self_stream) or not p.self_stream) and
            (Map.has_key?(c, :self_stream) and c.self_stream)

        stop_streaming =
          p != nil and (Map.has_key?(p, :self_stream) and p.self_stream) and
            (not Map.has_key?(c, :self_stream) or not c.self_stream)

        {joining, leaving, my_joining, my_leaving, start_streaming, stop_streaming}
      end

    new_state = %{
      state
      | voice_states: Map.put(state.voice_states, voice_state.user_id, voice_state)
    }

    cond do
      my_joining ->
        # If _I_ am joining
        S.cast_enable(state.speaker)
        S.cast_bare_message(state.speaker, "こんにちは、daidoquer2です。やさしくしてね。")

        new_state = %{
          new_state
          | num_users_in_channel: D.num_of_users_in_my_channel!(state.guild_id)
        }

        {:noreply, new_state}

      my_leaving ->
        # _I_ am leaving
        Logger.debug("Leaving #{state.guild_id}")
        S.cast_disable(state.speaker)
        {:noreply, new_state}

      joining ->
        # Someone joined the channel
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Joined (#{state.guild_id}) #{name}")
        S.cast_bare_message(state.speaker, "#{name}さんが参加しました。")

        new_state =
          if D.user!(voice_state.user_id).bot do
            new_state
          else
            num_users_in_channel = state.num_users_in_channel + 1
            Daidoquer2.GuildKiller.cancel_timer(state.guild_id)
            %{new_state | num_users_in_channel: num_users_in_channel}
          end

        {:noreply, new_state}

      leaving ->
        # Someone left the channel
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Left (#{state.guild_id}) #{name}")
        S.cast_bare_message(state.speaker, "#{name}さんが離れました。")

        new_state =
          if D.user!(voice_state.user_id).bot do
            new_state
          else
            num_users_in_channel = state.num_users_in_channel - 1

            if num_users_in_channel == 0 do
              Daidoquer2.GuildKiller.set_timer(state.guild_id)
            end

            %{new_state | num_users_in_channel: num_users_in_channel}
          end

        {:noreply, new_state}

      start_streaming ->
        # Someone started streaming
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Started streaming (#{state.guild_id}) #{name}")
        S.cast_bare_message(state.speaker, "#{name}さんがライブを始めました。")
        {:noreply, new_state}

      stop_streaming ->
        # Someone stoped streaming
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Stoped streaming (#{state.guild_id}) #{name}")
        S.cast_bare_message(state.speaker, "#{name}さんがライブを終了しました。")
        {:noreply, new_state}

      true ->
        {:noreply, new_state}
    end
  end

  def handle_cast({:join, msg}, state) do
    true = msg.guild_id == state.guild_id

    voice_channel_id = D.voice_channel_of_user!(state.guild_id, msg.author.id)

    new_state = %{
      state
      | voice_states:
          state.guild_id
          |> D.guild!()
          |> Map.get(:voice_states)
          |> Map.new(fn s -> {s.user_id, s} end)
    }

    cond do
      voice_channel_id == nil ->
        # The user doesn't belong to VC
        D.text_message(msg.channel_id, "Call from VC")
        {:noreply, new_state}

      voice_channel_id == D.voice_channel_of_user!(state.guild_id, D.me().id) ->
        # Already joined
        channel = D.channel!(msg.channel_id)
        D.text_message(msg.channel_id, "Already joined #{channel.name}")
        {:noreply, new_state}

      true ->
        # Really join
        D.join_voice_channel!(state.guild_id, voice_channel_id)
        channel = D.channel!(voice_channel_id)
        D.text_message(msg.channel_id, "Joined #{channel.name}")
        {:noreply, new_state}
    end
  end

  def handle_cast(:kick, state) do
    # Leave the channel now
    S.stop_speaking_and_clear_message_queue(state.speaker)
    S.schedule_leave(state.speaker)
    {:noreply, state}
  end

  def handle_cast({:leave, msg}, state) do
    voice_ready = D.voice_ready?(state.guild_id)
    user_vc_id = D.voice_channel_of_user!(state.guild_id, msg.author.id)
    my_vc_id = D.voice_channel_of_user!(state.guild_id, D.me().id)

    cond do
      not voice_ready ->
        # Not joined. Just ignore.
        :ignore

      user_vc_id != my_vc_id ->
        # User does not join the channel. Just ignore.
        Logger.debug("'!ddq leave' from another channel")
        D.text_message(msg.channel_id, "Call from the same VC channel")

      true ->
        S.stop_speaking_and_clear_message_queue(state.speaker)
        S.cast_bare_message(state.speaker, "。お相手はdaidoquer2でした。またね。")
        S.schedule_leave(state.speaker)
    end

    {:noreply, state}
  end

  def handle_cast(:voice_ready, state) do
    S.notify_voice_ready(state.speaker)
    {:noreply, state}
  end

  def handle_cast({:discord_message, msg}, state) do
    S.cast_discord_message(state.speaker, msg)
    {:noreply, state}
  end

  def handle_cast({:bare_message, text}, state) do
    S.cast_bare_message(state.speaker, text)
    {:noreply, state}
  end

  def handle_cast(:speaking_ended, state) do
    S.notify_speaking_ended(state.speaker)
    {:noreply, state}
  end

  def handle_call(:num_users_in_channel, _from, state) do
    {:reply, state.num_users_in_channel, state}
  end

  #####
  # Internals
end
