defmodule Daidoquer2.GuildSpeaker do
  use GenServer, restart: :transient

  require Logger

  alias Daidoquer2.AudioDirect, as: AD
  alias Daidoquer2.AudioFiltered, as: AF
  alias Daidoquer2.DiscordAPI, as: D
  alias Daidoquer2.GenAudio, as: GA
  alias Daidoquer2.CancellableTimer, as: T

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

  def notify_voice_server_update(pid, endpoint) do
    GenServer.cast(pid, {:voice_server_update, endpoint})
  end

  def stop_speaking_and_clear_message_queue(pid) do
    GenServer.cast(pid, :flush)
  end

  # Leave the VC once we finish speaking the current message
  def schedule_leave(pid) do
    GenServer.cast(pid, :schedule_leave)
  end

  def join_channel(pid, vchannel) do
    GenServer.cast(pid, {:join, vchannel})
  end

  def cast_reset_state(pid) do
    GenServer.cast(pid, :reset_state)
  end

  def notify_voice_incoming(pid) do
    GenServer.cast(pid, :voice_incoming)
  end

  def is_enabled(pid) do
    GenServer.call(pid, :enabled)
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
       voice_incoming_cnt: 0,
       endpoint: nil
     }}
  end

  def handle_cast(:enable, state) do
    {:noreply, %{state | enabled: true}}
  end

  def handle_cast(:disable, state) do
    disable(state)
  end

  def handle_cast(:reset_state, state) do
    state = reset_state(state)
    {:noreply, state}
  end

  def handle_cast(:voice_incoming, state) when state.audio_pid != nil do
    ms = ms_before_stop_low_voice()

    cond do
      ms == 0 ->
        {:noreply, state}

      state.voice_incoming_cnt < @trigger_voice_incoming_cnt ->
        {:noreply, %{state | voice_incoming_cnt: state.voice_incoming_cnt + 1}}

      true ->
        Logger.debug("Start low voice: #{state.guild_id}")
        AF.enable_low_voice(state.audio_pid)
        T.set_timer(:stop_low_voice, ms)
        {:noreply, %{state | voice_incoming_cnt: 0}}
    end
  end

  def handle_cast(:voice_incoming, state) do
    # Ignore
    {:noreply, state}
  end

  def handle_cast({:voice_server_update, endpoint}, state) do
    # Reset voice connection
    Logger.debug("VOICE_SERVER_UPDATE: #{state.guild_id}: #{endpoint}")
    vchannel = D.voice_channel_of_user!(state.guild_id, D.me().id)

    cond do
      vchannel == nil ->
        {:noreply, state}

      state.endpoint == nil ->
        {:noreply, %{state | endpoint: endpoint}}

      true ->
        {:noreply, new_state} = leave_vc(state)
        D.join_voice_channel!(state.guild_id, vchannel)
        {:noreply, %{new_state | enabled: true, msg_queue: state.msg_queue}}
    end
  end

  def handle_cast({:join, vchannel}, state) do
    D.join_voice_channel!(state.guild_id, vchannel)
    {:noreply, %{state | enabled: true}}
  end

  def handle_cast(event, state) when state.enabled do
    current_state = state.state

    case handle_state(current_state, event, state) do
      {:noreply, state} ->
        state = handle_state_transition(current_state, state.state, state)

        Logger.debug(
          "GuildSpeaker: #{state.guild_id}: handle_cast: #{inspect(event)}: #{inspect(current_state)} -> #{inspect(state.state)}"
        )

        {:noreply, state}

      res ->
        res
    end
  end

  def handle_cast(event, state) do
    Logger.debug("GuildSpeaker: #{state.guild_id}: handle_cast: #{inspect(event)}: disabled")
    {:noreply, state}
  end

  def handle_call(:enabled, _from, state) do
    {:reply, state.enabled, state}
  end

  def handle_info({:timeout, arg}, state) do
    T.dispatch(arg, state, __MODULE__)
  end

  #####
  # Timeout

  def handle_timeout(:stop_low_voice, state) when state.audio_pid != nil do
    AF.disable_low_voice(state.audio_pid)
    {:noreply, state}
  end

  def handle_timeout(:stop_low_voice, state) do
    # Ignore
    {:noreply, state}
  end

  def handle_timeout(:check_speaking, state) do
    :speaking = state.state

    case D.voice_playing?(state.guild_id) do
      true ->
        set_check_speaking_timer()
        {:noreply, state}

      false ->
        {:stop, :too_long_speaking_state}
    end
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
    state = queue_msg(state, msg)
    consume_queue(state)
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
    consume_queue(state)
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

  ####
  # State transitions

  def handle_state_transition(old_state, :speaking, state) when old_state != :speaking do
    D.start_listen_async(state.guild_id)
    set_check_speaking_timer()
    state
  end

  def handle_state_transition(:speaking, new_state, state) when new_state != :speaking do
    D.stop_listen_async(state.guild_id)
    cancel_check_speaking_timer()
    state
  end

  def handle_state_transition(_, _, state) do
    # Ignore
    state
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

  defp leave_vc(state) do
    Logger.debug("GuildSpeaker: #{state.guild_id}: stopping")
    D.leave_voice_channel(state.guild_id)
    disable(state)
  end

  defp disable(state) do
    {:noreply,
     %{state | enabled: false, state: :not_ready, msg_queue: :queue.new(), endpoint: nil}}
  end

  #####
  # Internals

  defp reset_state(state) do
    voice_connected = D.voice(state.guild_id) != nil

    if voice_connected do
      %{state | enabled: true}
    else
      %{state | enabled: false, state: :not_ready, msg_queue: :queue.new(), endpoint: nil}
    end
  end

  defp start_speaking(msg, state) do
    GA.cast_stop(state.audio_pid)
    guild_id = state.guild_id

    {text, uid} =
      case msg do
        {:discord_message, msg} -> format_discord_message(guild_id, msg)
        {:bare, text} -> {text, nil}
      end

    text =
      case Daidoquer2.MessageSanitizer.sanitize(text, guild_id) do
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
    try do
      res = HTTPoison.post!(url, text)
      {:ok, res.body}
    rescue
      e -> {:error, e}
    end
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
    {:ok, pid} =
      case ms_before_stop_low_voice() do
        0 ->
          # Disable low voice
          AD.start_link(src_data)

        _ ->
          # Enable low voice
          AF.start_link(src_data)
      end

    stream =
      Stream.unfold(nil, fn nil ->
        case GA.call_opus_data(pid) do
          nil -> nil
          val -> {val, nil}
        end
      end)

    D.voice_play!(guild_id, stream, :raw_s)
    pid
  end

  defp set_check_speaking_timer() do
    # FIXME: 30 sec. is enough?
    T.set_timer(:check_speaking, 30_000)
  end

  defp cancel_check_speaking_timer() do
    T.cancel_timer(:check_speaking)
  end

  defp ms_before_stop_low_voice() do
    Application.fetch_env!(:daidoquer2, :ms_before_stop_low_voice)
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
