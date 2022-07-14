###
# A --> B === A calls B
#
#  ignore_or_start_speaking_or_queue/3
#    : -> {:noreply, state}
#   |
#   |        handle_cast(:leave, state)
#   |         |
#   v         v
#  start_speaking_or_queue/3
#    : -> {:error, :voice_not_ready | :state_leaving | :sanitize_failed |
#                  :empty_msg | :invalid_state} |
#         {:error, {:cant_speak | :no_one_is_in, state}}
#         {:ok, state}
#   |
#   |                      handle_cast(:speaking_ended, _state)
#   |                       |
#   v                       v
#  speak_first_message_in_queue/1
#    : -> {:ok, state} | {:error, {:cant_speak | :no_one_is_in, state}}
#   |
#   v
#  start_speaking/3
#    : -> :ok | {:error, :cant_speak}
#
###
defmodule Daidoquer2.Guild do
  use GenServer, restart: :transient

  require Logger

  alias Daidoquer2.DiscordAPI, as: D

  #####
  # External API

  def start_link(guild_id) do
    GenServer.start_link(__MODULE__, guild_id)
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

  #####
  # GenServer callbacks

  def init(guild_id) do
    GenServer.cast(self(), :set_pid)

    voice_connected =
      try do
        D.voice(guild_id) != nil
      rescue
        e ->
          Logger.error("INIT: Failed to get voice status (#{guild_id}): #{inspect(e)}")
          false
      end

    Logger.debug("INIT: Voice status (#{guild_id}): #{voice_connected}")

    num_users_in_channel =
      if voice_connected do
        D.num_of_users_in_my_channel!(guild_id)
      else
        0
      end

    if voice_connected && num_users_in_channel == 0 do
      Daidoquer2.GuildKiller.set_timer(guild_id)
    end

    {:ok,
     %{
       guild_id: guild_id,
       msg_queue: :queue.new(),
       speaking: false,
       joining: false,
       leaving: false,
       voice_states: %{},
       num_users_in_channel: num_users_in_channel
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

  def handle_cast({:thread_create, channel}, state) do
    thread_name = channel.name
    user_name = D.display_name_of_user!(state.guild_id, channel.owner_id)

    Logger.debug("Thread created (#{state.guild_id}) #{thread_name} by #{user_name}")
    cast_bare_message(self(), "#{user_name}さんがスレッド「#{thread_name}」を作りました。")
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
        new_state = %{
          new_state
          | num_users_in_channel: D.num_of_users_in_my_channel!(state.guild_id)
        }

        {:noreply, new_state}

      my_leaving ->
        # If _I_ am leaving the channel, then shutdown this process.
        Logger.debug("Stopping #{state.guild_id}")
        {:stop, :normal, new_state}

      joining ->
        # Someone joined the channel
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Joined (#{state.guild_id}) #{name}")
        cast_bare_message(self(), "#{name}さんが参加しました。")

        num_users_in_channel = state.num_users_in_channel + 1
        new_state = %{new_state | num_users_in_channel: num_users_in_channel}

        Daidoquer2.GuildKiller.cancel_timer(state.guild_id)

        {:noreply, new_state}

      leaving ->
        # Someone left the channel
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Left (#{state.guild_id}) #{name}")
        cast_bare_message(self(), "#{name}さんが離れました。")

        num_users_in_channel = state.num_users_in_channel - 1
        new_state = %{new_state | num_users_in_channel: num_users_in_channel}

        if num_users_in_channel == 0 do
          Daidoquer2.GuildKiller.set_timer(state.guild_id)
        end

        {:noreply, new_state}

      start_streaming ->
        # Someone started streaming
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Started streaming (#{state.guild_id}) #{name}")
        cast_bare_message(self(), "#{name}さんがライブを始めました。")
        {:noreply, new_state}

      stop_streaming ->
        # Someone stoped streaming
        name = D.display_name_of_user!(state.guild_id, voice_state.user_id)
        Logger.debug("Stoped streaming (#{state.guild_id}) #{name}")
        cast_bare_message(self(), "#{name}さんがライブを終了しました。")
        {:noreply, new_state}

      true ->
        {:noreply, new_state}
    end
  end

  def handle_cast(:voice_ready, %{joining: true} = state) do
    cast_bare_message(self(), "こんにちは、daidoquer2です。やさしくしてね。")
    {:noreply, %{state | joining: false}}
  end

  def handle_cast(:voice_ready, state) do
    # Maybe reconnected. Just ignore.
    Logger.debug("Ignore VOICE_READY, maybe reconnected?")
    {:noreply, state}
  end

  def handle_cast({:join, msg}, state) do
    if msg.guild_id != state.guild_id do
      Logger.error("this message is not mine (#{state.guild_id}): #{inspect(msg)}")
      {:stop, {:invalid_message, msg, state}}
    else
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
          {:noreply, %{new_state | speaking: false, joining: true, msg_queue: :queue.new()}}
      end
    end
  end

  def handle_cast(:kick, state) do
    # Leave the channel now
    D.leave_voice_channel(state.guild_id)
    {:noreply, %{state | msg_queue: :queue.new(), speaking: false, leaving: false}}
  end

  def handle_cast({:leave, msg}, state) do
    voice_ready = try_make_voice_ready(state.guild_id)
    user_vc_id = D.voice_channel_of_user!(state.guild_id, msg.author.id)
    my_vc_id = D.voice_channel_of_user!(state.guild_id, D.me().id)

    cond do
      not voice_ready ->
        # Not joined. Just ignore.
        {:noreply, state}

      state.leaving ->
        # Already started to leave. Just ignore.
        {:noreply, state}

      user_vc_id != my_vc_id ->
        # User does not join the channel. Just ignore.
        Logger.debug("'!ddq leave' from another channel")
        D.text_message(msg.channel_id, "Call from the same VC channel")
        {:noreply, state}

      true ->
        if state.speaking do
          D.voice_stop(state.guild_id)
        end

        state = %{state | msg_queue: :queue.new()}

        case start_speaking_or_queue(state, "。お相手はdaidoquer2でした。またね。", nil) do
          {:ok, state} ->
            {:noreply, %{state | leaving: true}}

          {:error, _} ->
            # Failed to speak the announcement for some reason, so
            # leave the channel now.
            D.leave_voice_channel(state.guild_id)
            {:noreply, %{state | speaking: false, leaving: false}}
        end
    end
  end

  def handle_cast({:discord_message, msg}, state) do
    Logger.debug(inspect(msg))

    true = msg.guild_id == state.guild_id
    uid = msg.author.id

    # If msg has any attachments then say dummy
    if length(msg.attachments) != 0 do
      ignore_or_start_speaking_or_queue(state, Daidoquer2.MessageSanitizer.dummy(), uid)
    end

    content = msg.content

    # If msg has stickers, add them to the content.
    content =
      (msg.sticker_items || [])
      |> List.foldl(content, fn sticker, content -> "#{content} #{sticker.name}" end)

    ignore_or_start_speaking_or_queue(state, content, uid)
  end

  def handle_cast({:bare_message, text}, state) do
    ignore_or_start_speaking_or_queue(state, text)
  end

  def handle_cast(:speaking_ended, state) do
    if state.leaving && :queue.is_empty(state.msg_queue) do
      # Finished speaking farewell. Leave now.
      D.leave_voice_channel(state.guild_id)
      {:noreply, %{state | speaking: false, leaving: false}}
    else
      case speak_first_message_in_queue(state) do
        {:ok, state} ->
          {:noreply, state}

        {:error, {_e, state}} ->
          # Failed to speak the first message in the queue (for some reason),
          # so try the next one
          handle_cast(:speaking_ended, state)
      end
    end
  end

  defp replace_mention_with_display_name(text, guild_id) do
    Regex.replace(~r/<@!?([0-9]+)>/, text, fn whole, user_id_str ->
      {user_id, ""} = user_id_str |> Integer.parse()

      case D.display_name_of_user(guild_id, user_id) do
        {:ok, name} -> "@" <> name
        {:error, _} -> whole
      end
    end)
  end

  defp replace_channel_id_with_its_name(text) do
    Regex.replace(~r/<#!?([0-9]+)>/, text, fn whole, chan_id_str ->
      {chan_id, ""} = chan_id_str |> Integer.parse()

      case D.channel(chan_id) do
        {:ok, chan} -> "#" <> chan.name
        {:error, _} -> whole
      end
    end)
  end

  defp ignore_or_start_speaking_or_queue(state, text, uid \\ nil) do
    case start_speaking_or_queue(state, text, uid) do
      {:ok, state} ->
        {:noreply, state}

      {:error, :voice_not_ready} ->
        Logger.debug("Ignore message because voice is not ready")
        {:noreply, state}

      {:error, :state_leaving} ->
        Logger.debug("Ignore message because state is leaving")
        {:noreply, state}

      {:error, :sanitize_failed} ->
        Logger.debug("Ignore message because sanitization failed")
        {:noreply, state}

      {:error, :empty_msg} ->
        Logger.debug("Ignore message because it was empty")
        {:noreply, state}

      {:error, :invalid_state} ->
        {:noreply, state}

      {:error, {:cant_speak, state}} ->
        {:noreply, state}

      {:error, {:no_one_is_in, state}} ->
        {:noreply, state}
    end
  end

  defp start_speaking_or_queue(state, text, uid) do
    voice_ready = try_make_voice_ready(state.guild_id)

    cond do
      not voice_ready ->
        # Not joined. Just ignore.
        {:error, :voice_not_ready}

      state.leaving ->
        # Leaving now, so don't accept new messages.
        {:error, :state_leaving}

      true ->
        Logger.debug("Incoming (#{state.guild_id}): #{text}")

        {san_ok, text} =
          text
          |> replace_mention_with_display_name(state.guild_id)
          |> replace_channel_id_with_its_name()
          |> Daidoquer2.MessageSanitizer.sanitize()

        que_elm = %{
          text: text,
          uid: uid
        }

        cond do
          san_ok != :ok ->
            # Failed to sanitize the message
            {:error, :sanitize_failed}

          String.length(text) == 0 ->
            # Nothing to speak
            {:error, :empty_msg}

          D.voice_playing?(state.guild_id) or state.speaking ->
            # Currently speaking. Queue the message.
            {:ok, %{state | msg_queue: :queue.in(que_elm, state.msg_queue)}}

          :queue.is_empty(state.msg_queue) ->
            # Currently not speaking and the queue is empty. Speak the message.
            speak_first_message_in_queue(%{state | msg_queue: :queue.in(que_elm, state.msg_queue)})

          true ->
            Logger.error("Invalid state; not currently speaking, but queue is not empty.")
            {:error, :invalid_state}
        end
    end
  end

  defp speak_first_message_in_queue(state) do
    case :queue.out(state.msg_queue) do
      {:empty, _} ->
        {:ok, %{state | speaking: false}}

      {{:value, %{text: text, uid: uid}}, msg_queue} ->
        if state.num_users_in_channel == 0 do
          # No one is in my channel, so don't speak the message.
          # Just throw it away.
          Logger.debug("No one is in the channel. Don't speak.")
          {:error, {:no_one_is_in, %{state | msg_queue: msg_queue}}}
        else
          chara = select_chara_from_uid(uid)

          case start_speaking(state.guild_id, text, chara) do
            :ok ->
              {:ok, %{state | speaking: true, msg_queue: msg_queue}}

            {:error, e} ->
              {:error, {e, %{state | msg_queue: msg_queue}}}
          end
        end
    end
  end

  defp select_chara_from_uid(uid) do
    if uid == nil do
      {:post, Application.get_env(:daidoquer2, :default_post_url, "http://localhost:8399")}
    else
      uid2chara = Application.get_env(:daidoquer2, :uid2chara, %{})
      preset_chara = Application.get_env(:daidoquer2, :preset_chara, %{})

      case uid2chara |> Map.fetch(uid) do
        {:ok, chara} -> chara
        :error -> preset_chara |> Enum.fetch!(rem(uid, length(preset_chara)))
      end
    end
  end

  defp tts_via_google(text, chara) do
    {:ok, token} = Goth.Token.for_scope("https://www.googleapis.com/auth/cloud-platform")
    client = GoogleApi.TextToSpeech.V1.Connection.new(token.token)

    request = %GoogleApi.TextToSpeech.V1.Model.SynthesizeSpeechRequest{
      input: %GoogleApi.TextToSpeech.V1.Model.SynthesisInput{
        text: text
      },
      voice: %GoogleApi.TextToSpeech.V1.Model.VoiceSelectionParams{
        languageCode: "ja-JP",
        name:
          case chara do
            0 -> "ja-JP-Wavenet-A"
            1 -> "ja-JP-Wavenet-B"
            2 -> "ja-JP-Wavenet-C"
            _ -> "ja-JP-Wavenet-D"
          end
      },
      audioConfig: %GoogleApi.TextToSpeech.V1.Model.AudioConfig{
        audioEncoding: "MP3"
      }
    }

    {:ok, response} =
      GoogleApi.TextToSpeech.V1.Api.Text.texttospeech_text_synthesize(client, body: request)

    Base.decode64!(response.audioContent)
  end

  defp tts_via_post(text, url) do
    res = HTTPoison.post!(url, text)
    res.body
  end

  defp tts_via_sushikicom(text, param) do
    key = System.fetch_env!("SUSHIKICOM_API_TOKEN")

    res =
      HTTPoison.post!(
        "https://api.su-shiki.com/v2/voicevox/audio/" <> param,
        {:form, [{"text", text}, {"key", key}]}
      )

    res.body
  end

  defp tts_via_voicevox_engine(text, url, speaker) do
    url1 = construct_url(url, "/audio_query", [{"text", text}, {"speaker", speaker}])
    url2 = construct_url(url, "/synthesis", [{"speaker", speaker}])

    with {:ok, res1} <- post(url1, ""),
         {:ok, res2} <- post(url2, res1.body, [{"Content-Type", "application/json"}]) do
      res2.body
    else
      {:error, res} -> raise inspect(res)
    end
  end

  defp start_speaking(guild_id, text, chara) do
    try do
      true = D.voice_ready?(guild_id)

      speech =
        case chara do
          {:post, url} ->
            tts_via_post(text, url)

          {:google, chara} ->
            tts_via_google(text, chara)

          {:sushikicom, param} ->
            tts_via_sushikicom(text, param)

          {:voicevox_engine, url, speaker} ->
            tts_via_voicevox_engine(text, url, speaker)
        end

      # Here, we intentionally do not use the option :pipe for D.voice_play!,
      # because it does not work properly when audio data is short (about <2 seconds).
      # I belive that this is NOT a problem of :audio_frames_per_burst, which is
      # explicitly stated in the Nostrum document, but a problem of Port of Elixir.
      # When the audio data is short, FFmpeg's output finishes before the buffer of Port
      # becomes full. However, FFmpeg cannot exit (i.e., Port cannot know when FFmpeg
      # finishes its output) when we use :pipe, so it causes timeout of
      # Nostrum.Voice.Audio.try_send_data/3.
      # To avoid this situation, I use :url here, because FFmpeg can exit by doing so.
      Logger.debug("Speaking (#{guild_id},#{inspect(chara)}): #{text}")
      tmpfile_path = Application.fetch_env!(:daidoquer2, :tmpfile_path)
      File.write(tmpfile_path, speech, [:binary])
      D.voice_play!(guild_id, tmpfile_path, :url, realtime: false)

      :ok
    rescue
      e ->
        Logger.error(
          "Can't speak #{inspect(text)} (#{guild_id},#{inspect(chara)}): #{inspect(e)}"
        )

        {:error, :cant_speak}
    end
  end

  defp try_make_voice_ready(guild_id) do
    if D.voice_ready?(guild_id) do
      # Already ready. Do nothing.
      true
    else
      voice_channel_id = D.voice_channel_of_user!(guild_id, D.me().id)

      if voice_channel_id == nil do
        # I don't belong to any voice channel, so can't make voice ready.
        false
      else
        # Not voice ready BUT I belong to a voice channel.
        # (Maybe due to Discord's connection problem?)
        # Try to re-join the channel
        Logger.debug("Try re-joining to voice channel")
        D.join_voice_channel!(guild_id, voice_channel_id)
        # FIXME wait until voice becomes ready
        D.voice_ready?(guild_id)
      end
    end
  end

  defp construct_url(baseurl, endpoint, query) do
    url = URI.parse(baseurl)
    url = URI.merge(url, endpoint) |> to_string
    param = URI.encode_query(query)
    url <> "?" <> param
  end

  defp post(url, body, headers \\ []) do
    case HTTPoison.post(url, body, headers) do
      {:ok, res} ->
        if res.status_code == 200 do
          {:ok, res}
        else
          {:error, {:status, res}}
        end

      {:error, res} ->
        {:error, {:post, res}}
    end
  end
end
