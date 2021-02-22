defmodule Daidoquer2.Guild do
  use GenServer, restart: :transient

  require Logger

  alias Nostrum.Api
  alias Nostrum.Voice
  alias Nostrum.Cache.Me

  @message_length_limit 100

  #####
  # External API

  def start_link(guild_id) do
    GenServer.start_link(__MODULE__, guild_id)
  end

  def join_channel(pid, msg) do
    GenServer.cast(pid, {:join, msg})
  end

  def leave_channel(pid) do
    GenServer.cast(pid, :leave)
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

  #####
  # GenServer callbacks

  def init(guild_id) do
    GenServer.cast(self(), :set_pid)

    {:ok,
     %{
       guild_id: guild_id,
       msg_queue: :queue.new(),
       tmpfile_path: nil,
       leaving: false,
       voice_states: %{}
     }}
  end

  def handle_cast(:set_pid, state) do
    gproc_id = Daidoquer2.GuildRegistry.get_gproc_id_for_guild(state.guild_id)

    try do
      :gproc.ensure_reg(gproc_id)
      {:noreply, state}
    catch
      :error, _ ->
        # Process duplicates w.r.t. guild.
        # Here should be unreachable thanks to Daidoquer2.GuildRegistry
        Logger.error("Unreachable: Guild duplicated; some messages may be lost")
        {:stop, :normal, state}
    end
  end

  def handle_cast({:voice_state_updated, voice_state}, state) do
    true = voice_state.guild_id == state.guild_id

    {joining, leaving, my_joining, my_leaving} =
      with p <- state.voice_states |> Map.get(voice_state.user_id),
           c <- voice_state,
           my_user_id <- Me.get().id,
           ch <- get_voice_channel_of(state.guild_id, my_user_id) do
        joining = p != nil and ch != nil and p.channel_id != c.channel_id and c.channel_id == ch
        leaving = p != nil and ch != nil and p.channel_id != c.channel_id and p.channel_id == ch
        about_me = voice_state.user_id == my_user_id
        my_joining = about_me and joining
        my_leaving = about_me and (leaving or ch == nil)
        {joining, leaving, my_joining, my_leaving}
      end

    new_state = %{
      state
      | voice_states: Map.put(state.voice_states, voice_state.user_id, voice_state)
    }

    cond do
      my_joining ->
        # If _I_ am joining, then ignore.
        {:noreply, new_state}

      my_leaving ->
        # If _I_ am leaving the channel, then shutdown this process.
        Logger.debug("Stopping #{state.guild_id}")
        {:stop, :normal, new_state}

      joining ->
        # Someone joined the channel
        {:ok, name} = get_display_name(voice_state.guild_id, voice_state.user_id)
        Logger.debug("Joined (#{state.guild_id}) #{name}")
        cast_bare_message(self(), "#{name}さんが参加しました。")
        {:noreply, new_state}

      leaving ->
        # Someone left the channel
        {:ok, name} = get_display_name(voice_state.guild_id, voice_state.user_id)
        Logger.debug("Left (#{state.guild_id}) #{name}")
        cast_bare_message(self(), "#{name}さんが離れました。")
        {:noreply, new_state}

      true ->
        {:noreply, new_state}
    end
  end

  def handle_cast(:voice_ready, state) do
    cast_bare_message(self(), "こんにちは、daidoquer2です。やさしくしてね。")
    {:noreply, state}
  end

  def handle_cast({:join, msg}, state) do
    if msg.guild_id != state.guild_id do
      Logger.error("this message is not mine (#{state.guild_id}): #{inspect(msg)}")
      {:stop, {:invalid_message, msg, state}}
    else
      voice_channel_id = get_voice_channel_of(state.guild_id, msg.author.id)

      new_state = %{
        state
        | voice_states:
            state.guild_id
            |> Nostrum.Cache.GuildCache.get!()
            |> Map.get(:voice_states)
            |> Map.new(fn s -> {s.user_id, s} end)
      }

      cond do
        voice_channel_id == nil ->
          # The user doesn't belong to VC
          Api.create_message(msg.channel_id, "Call from VC")
          {:noreply, new_state}

        voice_channel_id == get_voice_channel_of(state.guild_id, Me.get().id) ->
          # Already joined
          channel = Api.get_channel!(msg.channel_id)
          Api.create_message(msg.channel_id, "Already joined #{channel.name}")
          {:noreply, new_state}

        true ->
          # Really join
          :ok = Voice.join_channel(state.guild_id, voice_channel_id)
          channel = Api.get_channel!(voice_channel_id)
          Api.create_message(msg.channel_id, "Joined #{channel.name}")
          {:noreply, %{new_state | tmpfile_path: nil, msg_queue: :queue.new()}}
      end
    end
  end

  def handle_cast(:leave, state) do
    cond do
      not Voice.ready?(state.guild_id) ->
        # Not joined. Just ignore.
        {:noreply, state}

      state.leaving ->
        # Already started to leave. Just ignore.
        {:noreply, state}

      true ->
        if state.tmpfile_path != nil do
          Voice.stop(state.guild_id)
        end

        state = %{state | msg_queue: :queue.new()}
        {:noreply, state} = ignore_or_start_speaking_or_queue(state, "。お相手はdaidoquer2でした。またね。")
        {:noreply, %{state | leaving: true}}
    end
  end

  def handle_cast({:discord_message, msg}, state) do
    true = msg.guild_id == state.guild_id
    ignore_or_start_speaking_or_queue(state, msg.content)
  end

  def handle_cast({:bare_message, text}, state) do
    ignore_or_start_speaking_or_queue(state, text)
  end

  def handle_cast(:speaking_ended, state) do
    if state.tmpfile_path != nil do
      File.rm(state.tmpfile_path)
    end

    if state.leaving && :queue.is_empty(state.msg_queue) do
      # Finished speaking farewell. Leave now.
      Voice.leave_channel(state.guild_id)
      {:noreply, %{state | tmpfile_path: nil, leaving: false}}
    else
      speak_message_in_queue(state)
    end
  end

  defp get_voice_channel_of(guild_id, user_id) do
    guild_id
    |> Nostrum.Cache.GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == user_id end)
    |> Map.get(:channel_id)
  end

  defp get_display_name(guild_id, user_id) do
    case Nostrum.Api.get_guild_member(guild_id, user_id) do
      {:ok, member} -> {:ok, member.nick || member.user.username}
      error -> error
    end
  end

  defp replace_mention_with_display_name(text, guild_id) do
    Regex.replace(~r/<@!?([0-9]+)>/, text, fn whole, user_id_str ->
      {user_id, ""} = user_id_str |> Integer.parse()

      case get_display_name(guild_id, user_id) do
        {:ok, name} -> "@" <> name
        {:error, _} -> whole
      end
    end)
  end

  defp ignore_or_start_speaking_or_queue(state, text) do
    cond do
      not Voice.ready?(state.guild_id) ->
        # Not joined. Just ignore.
        {:noreply, state}

      state.leaving ->
        # Leaving now, so don't accept new messages.
        {:noreply, state}

      true ->
        Logger.debug("Incoming (#{state.guild_id}): #{text}")

        {san_ok, text} =
          text
          |> replace_mention_with_display_name(state.guild_id)
          |> Daidoquer2.MessageSanitizer.sanitize()

        cond do
          san_ok != :ok ->
            # Failed to sanitize the message. Just ignore.
            {:noreply, state}

          String.length(text) == 0 ->
            # Nothing to speak. Just ignore.
            {:noreply, state}

          Voice.playing?(state.guild_id) or state.tmpfile_path != nil ->
            # Currently speaking. Queue the message.
            {:noreply, %{state | msg_queue: :queue.in(text, state.msg_queue)}}

          :queue.is_empty(state.msg_queue) ->
            # Currently not speaking and the queue is empty. Speak the message.
            speak_message_in_queue(%{state | msg_queue: :queue.in(text, state.msg_queue)})

          true ->
            Logger.error("Invalid state; not currently speaking, but queue is not empty.")
            {:noreply, state}
        end
    end
  end

  defp speak_message_in_queue(state) do
    case :queue.out(state.msg_queue) do
      {:empty, _} ->
        {:noreply, %{state | tmpfile_path: nil}}

      {{:value, msg}, msg_queue} ->
        case start_speaking(state.guild_id, msg) do
          {:ok, tmpfile_path} ->
            {:noreply, %{state | tmpfile_path: tmpfile_path, msg_queue: msg_queue}}

          {:error, _} ->
            speak_message_in_queue(%{state | msg_queue: msg_queue})
        end
    end
  end

  defp start_speaking(guild_id, text) do
    try do
      true = Voice.ready?(guild_id)

      res = HTTPoison.post!("http://localhost:8399", text)

      # FIXME: `Voice.play(guild_id, File.read!("hoge.wav"), :pipe)` doesn't work.
      {:ok, fd, file_path} = Temp.open("daidoquer2")
      IO.binwrite(fd, res.body)
      File.close(fd)

      Logger.debug("Speaking (#{guild_id}): #{text}")
      :ok = Voice.play(guild_id, file_path, :url, realtime: false)
      {:ok, file_path}
    rescue
      e ->
        Logger.error("Can't speak #{inspect(text)} (#{guild_id}): #{inspect(e)}")
        {:error, e}
    end
  end
end
