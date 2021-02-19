defmodule Daidoquer2.Guild do
  use GenServer, restart: :transient

  require Logger

  alias Nostrum.Api
  alias Nostrum.Voice
  alias Nostrum.Cache.Me

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

  def notify_speaking_ended(pid) do
    GenServer.cast(pid, :speaking_ended)
  end

  def notify_voice_state_updated(pid, voice_state) do
    GenServer.cast(pid, {:voice_state_updated, voice_state})
  end

  #####
  # GenServer callbacks

  def init(guild_id) do
    GenServer.cast(self(), :set_pid)
    {:ok, %{guild_id: guild_id, msg_queue: :queue.new(), tmpfile_path: nil, voice_state: nil}}
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

    prev = state.voice_state
    cur = voice_state

    cond do
      (prev == nil or prev.channel_id == nil) and cur.channel_id != nil ->
        # Joined channel
        GenServer.cast(self(), {:bare_message, "こんにちは、daidoquer2です。やさしくしてね。"})

      true ->
        nil
    end

    {:noreply, %{state | voice_state: voice_state}}
  end

  def handle_cast({:join, msg}, state) do
    if msg.guild_id != state.guild_id do
      Logger.error("this message is not mine (#{state.guild_id}): #{inspect(msg)}")
      {:stop, {:invalid_message, msg, state}}
    else
      voice_channel_id = get_voice_channel_of(state.guild_id, msg.author.id)

      cond do
        voice_channel_id == nil ->
          # The user doesn't belong to VC
          Api.create_message(msg.channel_id, "Call from VC")
          {:noreply, state}

        voice_channel_id == get_voice_channel_of(state.guild_id, Me.get().id) ->
          # Already joined
          channel = Api.get_channel!(msg.channel_id)
          Api.create_message(msg.channel_id, "Already joined #{channel.name}")
          {:noreply, state}

        true ->
          # Really join
          :ok = Voice.join_channel(state.guild_id, voice_channel_id)
          channel = Api.get_channel!(msg.channel_id)
          Api.create_message(msg.channel_id, "Joined #{channel.name}")
          {:noreply, %{state | tmpfile_path: nil, msg_queue: :queue.new()}}
      end
    end
  end

  def handle_cast(:leave, state) do
    Voice.leave_channel(state.guild_id)
    {:noreply, state}
  end

  def handle_cast({:discord_message, msg}, state) do
    true = msg.guild_id == state.guild_id

    unless Voice.ready?(state.guild_id) do
      # Not joined. Just ignore.
      {:noreply, state}
    else
      # FIXME: format msg.content
      start_speaking_or_queue(state, msg.content)
    end
  end

  def handle_cast({:bare_message, text}, state) do
    unless Voice.ready?(state.guild_id) do
      # Not joined. Just ignore.
      Logger.debug("#{text}")
      {:noreply, state}
    else
      start_speaking_or_queue(state, text)
    end
  end

  def handle_cast(:speaking_ended, state) do
    if state.tmpfile_path != nil do
      File.rm(state.tmpfile_path)
    end

    case :queue.out(state.msg_queue) do
      {:empty, _} ->
        {:noreply, %{state | tmpfile_path: nil}}

      {{:value, msg}, msg_queue} ->
        tmpfile_path = speak(state.guild_id, msg)
        {:noreply, %{state | tmpfile_path: tmpfile_path, msg_queue: msg_queue}}
    end
  end

  defp get_voice_channel_of(guild_id, user_id) do
    guild_id
    |> Nostrum.Cache.GuildCache.get!()
    |> Map.get(:voice_states)
    |> Enum.find(%{}, fn v -> v.user_id == user_id end)
    |> Map.get(:channel_id)
  end

  defp start_speaking_or_queue(state, text) do
    cond do
      Voice.playing?(state.guild_id) or state.tmpfile_path != nil ->
        # Currently speaking. Queue the message.
        {:noreply, %{state | msg_queue: :queue.in(text, state.msg_queue)}}

      :queue.is_empty(state.msg_queue) ->
        # Currently not speaking and the queue is empty. Speak the message.
        tmpfile_path = speak(state.guild_id, text)
        {:noreply, %{state | tmpfile_path: tmpfile_path}}
    end
  end

  defp speak(guild_id, text) do
    true = Voice.ready?(guild_id)

    res = HTTPoison.post!("http://localhost:8399", text)

    # FIXME: `Voice.play(guild_id, File.read!("hoge.wav"), :pipe)` doesn't work.
    {:ok, fd, file_path} = Temp.open("daidoquer2")
    IO.binwrite(fd, res.body)
    File.close(fd)

    :ok = Voice.play(guild_id, file_path)
    file_path
  end
end
