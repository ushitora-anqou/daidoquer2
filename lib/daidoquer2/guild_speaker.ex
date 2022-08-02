defmodule Daidoquer2.GuildSpeaker do
  use GenServer, restart: :transient

  require Logger

  alias Daidoquer2.Audio, as: A
  alias Daidoquer2.DiscordAPI, as: D
  alias Daidoquer2.Guild, as: G
  alias Daidoquer2.GuildTimer, as: T

  @trigger_voice_incoming_cnt 25

  #####
  # External API

  def name(guild_id) do
    {:via, Registry, {Registry.Speaker, guild_id}}
  end

  def start_link(guild_id) do
    GenServer.start_link(__MODULE__, guild_id, name: name(guild_id))
  end

  def cast_discord_message(pid, msg) do
    GenServer.cast(pid, {:message, {:discord_message, msg}})
  end

  def cast_bare_message(pid, text) do
    GenServer.cast(pid, {:message, {:bare, text}})
  end

  def notify_speaking_ended(pid) do
    GenServer.cast(pid, :speaking_ended)
  end

  def notify_voice_ready(pid) do
    GenServer.cast(pid, :voice_ready)
  end

  def stop_speaking_and_clear_message_queue(pid) do
    GenServer.cast(pid, :flush)
  end

  # Leave the VC once we finish speaking the current message
  def schedule_leave(pid) do
    GenServer.cast(pid, :schedule_leave)
  end

  def cast_enable(pid) do
    GenServer.cast(pid, :enable)
  end

  def cast_disable(pid) do
    GenServer.cast(pid, :disable)
  end

  def notify_voice_incoming(pid) do
    GenServer.cast(pid, :voice_incoming)
  end

  def callback_timeout(key, guild_id, timer_ref) do
    GenServer.cast(name(guild_id), {:timeout, key, timer_ref})
  end

  #####
  # GenServer callbacks

  def init(guild_id) do
    voice_ready = D.voice_ready?(guild_id)
    initial_state = if voice_ready, do: :ready, else: :not_ready
    Logger.debug("GuildSpeaker: #{guild_id}: init: initial_state: #{inspect(initial_state)}")

    D.stop_listen_async(guild_id)

    {:ok,
     %{
       guild_id: guild_id,
       msg_queue: :queue.new(),
       state: initial_state,
       enabled: false,
       audio_pid: nil,
       voice_incoming_cnt: 0
     }}
  end

  def handle_cast(:enable, state) do
    {:noreply, %{state | enabled: true}}
  end

  def handle_cast(:disable, state) do
    disable(state)
  end

  def handle_cast(:voice_incoming, state) when state.audio_pid != nil do
    ms = Application.fetch_env!(:daidoquer2, :ms_before_stop_low_voice)

    cond do
      ms == 0 ->
        {:noreply, state}

      state.voice_incoming_cnt < @trigger_voice_incoming_cnt ->
        {:noreply, %{state | voice_incoming_cnt: state.voice_incoming_cnt + 1}}

      true ->
        Logger.debug("Start low voice: #{state.guild_id}")
        A.enable_low_voice(state.audio_pid)
        T.set_timer(state.guild_id, :stop_low_voice, ms, __MODULE__, :callback_timeout)
        {:noreply, %{state | voice_incoming_cnt: 0}}
    end
  end

  def handle_cast(:voice_incoming, state) do
    # Ignore
    {:noreply, state}
  end

  def handle_cast({:timeout, key, timer_ref}, state) do
    case T.check_timeout(timer_ref) do
      false ->
        # Ignore fake timeout
        {:noreply, state}

      true ->
        handle_timeout(key, state)
    end
  end

  def handle_cast(event, state) do
    if state.enabled do
      res = handle_state(state.state, event, state)

      next_state =
        case res do
          {:noreply, state} -> state.state
          {:stop, :normal, state} -> state.state
        end

      Logger.debug(
        "GuildSpeaker: #{state.guild_id}: handle_cast: #{inspect(event)}: #{inspect(state.state)} -> #{inspect(next_state)}"
      )

      res
    else
      Logger.debug("GuildSpeaker: #{state.guild_id}: handle_cast: #{inspect(event)}: disabled")
      {:noreply, state}
    end
  end

  #####
  # Timeout

  def handle_timeout(:stop_low_voice, state) when state.audio_pid != nil do
    A.disable_low_voice(state.audio_pid)
    {:noreply, state}
  end

  def handle_timeout(:stop_low_voice, state) do
    # Ignore
    {:noreply, state}
  end

  #####
  ## STATE = :not_ready
  #####

  def handle_state(:not_ready, {:message, msg = {:bare, _}}, state) do
    # Queue only bare messages to speak out the welcome message
    state = queue_msg(state, msg)
    {:noreply, state}
  end

  def handle_state(:not_ready, {:message, _msg}, state) do
    # Ignore other messages
    {:noreply, state}
  end

  def handle_state(:not_ready, :voice_ready, state) do
    consume_queue(state)
  end

  def handle_state(:not_ready, :flush, state) do
    # Ignore
    {:noreply, state}
  end

  def handle_state(:not_ready, :schedule_leave, state) do
    leave_vc(state)
  end

  #####
  ## STATE = :ready
  #####

  def handle_state(:ready, :voice_ready, state) do
    # When ddq is in a VC, moving it to or sending !ddq join from another VC will send :voice_ready.
    # Let's ignore this message.
    {:noreply, state}
  end

  def handle_state(:ready, {:message, msg}, state) do
    # Start speaking the message
    case start_speaking(msg, state) do
      {:ok, state} ->
        D.start_listen_async(state.guild_id)
        {:noreply, %{state | state: :speaking}}

      {:error, _error} ->
        {:noreply, %{state | state: :ready}}
    end
  end

  def handle_state(:ready, :flush, state) do
    # Ignore
    {:noreply, state}
  end

  def handle_state(:ready, :schedule_leave, state) do
    leave_vc(state)
  end

  #####
  ## STATE = :speaking
  #####

  def handle_state(:speaking, :voice_ready, state) do
    # When ddq is in a VC, moving it to or sending !ddq join from another VC will send :voice_ready.
    # Let's ignore this message.
    {:noreply, state}
  end

  def handle_state(:speaking, {:message, msg}, state) do
    # Currently speaking. Queue the message.
    state = queue_msg(state, msg)
    {:noreply, state}
  end

  def handle_state(:speaking, :speaking_ended, state) do
    case consume_queue(state) do
      {_, %{state: :ready} = state} ->
        D.stop_listen_async(state.guild_id)
        {:noreply, state}

      res ->
        res
    end
  end

  def handle_state(:speaking, :flush, state) do
    D.voice_stop(state.guild_id)
    # The next state is not :ready but :speaking because we need to wait :speaking_ended
    {:noreply, %{state | state: :speaking, msg_queue: :queue.new()}}
  end

  def handle_state(:speaking, :schedule_leave, state) do
    state = queue_msg(state, :leave)
    {:noreply, state}
  end

  #####
  # Actions for handle_state

  defp queue_msg(state, msg) do
    num_users = D.num_of_users_in_my_channel!(state.guild_id)

    if msg != :leave and num_users == 0 do
      # No need to speak
      Logger.debug("GuildSpeaker: #{state.guild_id}: no need to speak: #{inspect(msg)}")
      state
    else
      %{state | msg_queue: :queue.in(msg, state.msg_queue)}
    end
  end

  defp consume_queue(state) do
    case :queue.out(state.msg_queue) do
      {:empty, _} ->
        {:noreply, %{state | state: :ready}}

      {{:value, :leave}, _} ->
        leave_vc(state)

      {{:value, msg}, msg_queue} ->
        state = %{state | state: :speaking, msg_queue: msg_queue}

        case start_speaking(msg, state) do
          {:ok, state} -> {:noreply, state}
          {:error, _error} -> consume_queue(state)
        end
    end
  end

  def leave_vc(state) do
    Logger.debug("GuildSpeaker: #{state.guild_id}: stopping")
    D.leave_voice_channel(state.guild_id)
    disable(state)
  end

  def disable(state) do
    {:noreply, %{state | enabled: false, state: :not_ready, msg_queue: :queue.new()}}
  end

  #####
  # Internals

  defp start_speaking(msg, state) do
    A.cast_stop(state.audio_pid)
    guild_id = state.guild_id

    {text, uid} =
      case msg do
        {:discord_message, msg} -> format_discord_message(guild_id, msg)
        {:bare, text} -> {text, nil}
      end

    text =
      case text
           |> replace_mention_with_display_name(guild_id)
           |> replace_channel_id_with_its_name()
           |> Daidoquer2.MessageSanitizer.sanitize() do
        {:ok, text} -> text
        _ -> ""
      end

    if text == "" do
      {:error, :speak_empty}
    else
      chara = select_chara_from_uid(guild_id, uid)

      case do_start_speaking(guild_id, text, chara) do
        {:ok, audio_pid} -> {:ok, %{state | audio_pid: audio_pid}}
        error -> error
      end
    end
  end

  defp format_discord_message(guild_id, msg) do
    true = msg.guild_id == guild_id
    content = msg.content

    # If msg has any attachments then say dummy
    content =
      if msg.attachments == [], do: content, else: Daidoquer2.MessageSanitizer.dummy() <> content

    # If msg has stickers, add them to the content.
    content =
      (msg.sticker_items || [])
      |> List.foldl(content, fn sticker, content -> "#{content} #{sticker.name}" end)

    {content, msg.author.id}
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

  defp select_chara_from_uid(_, nil) do
    Application.fetch_env!(:daidoquer2, :announcer)
  end

  defp select_chara_from_uid(guild_id, uid) do
    uid2chara = Application.get_env(:daidoquer2, :uid2chara, %{})
    role2chara = Application.get_env(:daidoquer2, :role2chara, %{})

    case Map.fetch(uid2chara, uid) do
      {:ok, chara} ->
        chara

      :error ->
        roles = D.roles_of_user!(guild_id, uid)

        case Enum.find_value(roles, fn role -> Map.get(role2chara, role.name) end) do
          nil ->
            {_role, chara} = Enum.at(role2chara, rem(uid, map_size(role2chara)))
            chara

          chara ->
            chara
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

    {:ok, Base.decode64!(response.audioContent)}
  end

  defp tts_via_post(text, url) do
    res = HTTPoison.post!(url, text)
    {:ok, res.body}
  end

  defp tts_via_sushikicom(text, param) do
    key = System.fetch_env!("SUSHIKICOM_API_TOKEN")

    res =
      HTTPoison.post!(
        "https://api.su-shiki.com/v2/voicevox/audio/" <> param,
        {:form, [{"text", text}, {"key", key}]}
      )

    {:ok, res.body}
  end

  defp tts_via_voicevox_engine(text, url, speaker) do
    url1 = construct_url(url, "/audio_query", [{"text", text}, {"speaker", speaker}])
    url2 = construct_url(url, "/synthesis", [{"speaker", speaker}])

    with {:ok, res1} <- post(url1, ""),
         {:ok, res2} <- post(url2, res1.body, [{"Content-Type", "application/json"}]) do
      {:ok, res2.body}
      # else -> {:error, error}
    end
  end

  defp do_start_speaking(guild_id, text, chara) do
    true = D.voice_ready?(guild_id)

    speech_res =
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

    case speech_res do
      {:ok, speech} ->
        Logger.debug("Speaking (#{guild_id},#{inspect(chara)}): #{text}")
        audio_pid = start_playing(guild_id, speech)
        {:ok, audio_pid}

      {:error, e} ->
        Logger.error(
          "Can't speak #{inspect(text)} (#{guild_id},#{inspect(chara)}): #{inspect(e)}"
        )

        {:error, :cant_speak}
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

  defp start_playing(guild_id, src_data) do
    {:ok, pid} = A.start_link(src_data)

    stream =
      Stream.unfold(nil, fn nil ->
        case A.call_opus_data(pid) do
          nil -> nil
          val -> {val, nil}
        end
      end)

    D.voice_play!(guild_id, stream, :raw_s)
    pid
  end

  # defp try_make_voice_ready(guild_id) do
  #  if D.voice_ready?(guild_id) do
  #    # Already ready. Do nothing.
  #    true
  #  else
  #    voice_channel_id = D.voice_channel_of_user!(guild_id, D.me().id)
  #
  #    if voice_channel_id == nil do
  #      # I don't belong to any voice channel, so can't make voice ready.
  #      false
  #    else
  #      # Not voice ready BUT I belong to a voice channel.
  #      # (Maybe due to Discord's connection problem?)
  #      # Try to re-join the channel
  #      Logger.debug("Try re-joining to voice channel")
  #      D.join_voice_channel!(guild_id, voice_channel_id)
  #      # FIXME wait until voice becomes ready
  #      D.voice_ready?(guild_id)
  #    end
  #  end
  # end
end
