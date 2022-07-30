# Architecture:
#   src -> |FFmpeg| -> wav -> |Filter| -> filtered -> |FFmpeg| -> opus
#
defmodule Daidoquer2.Audio do
  use GenServer, restart: :transient

  require Logger

  #####
  # External API

  def name(guild_id) do
    {:via, Registry, {Registry.Audio, guild_id}}
  end

  def start_link(guild_id, src_data) do
    GenServer.start_link(__MODULE__, src_data, name: name(guild_id))
  end

  def cast_stop(pid) do
    GenServer.cast(pid, :stop)
  end

  def call_opus_data(pid) do
    GenServer.call(pid, :opus_data)
  end

  #####
  # GenServer callbacks

  def init(src_data) do
    ffmpeg_path = Application.fetch_env!(:daidoquer2, :ffmpeg_path)
    ffmpeg_options1 = Application.fetch_env!(:daidoquer2, :ffmpeg_options1) |> List.flatten()
    ffmpeg_options2 = Application.fetch_env!(:daidoquer2, :ffmpeg_options2) |> List.flatten()

    {:ok, pid1, os_pid1} =
      :exec.run([ffmpeg_path] ++ ffmpeg_options1, [:stdin, :stdout, {:stderr, :print}, :monitor])

    {:ok, pid2, os_pid2} =
      :exec.run([ffmpeg_path] ++ ffmpeg_options2, [:stdin, :stdout, {:stderr, :print}, :monitor])

    # NOTE: Just executing :exec.send(pid1, src_data) returns error (EINVAL) for write(2).
    # I don't know why.
    send_src(pid1, src_data)

    {:ok,
     %{
       pid1: pid1,
       pid2: pid2,
       os_pid1: os_pid1,
       os_pid2: os_pid2,
       q: :queue.new(),
       awaiter: nil,
       finished: false
     }}
  end

  def handle_cast(:stop, state) do
    Logger.debug("Audio stopped: #{inspect(state)}")

    if state.awaiter != nil do
      GenServer.reply(state.awaiter, nil)
    end

    {:stop, :normal, state}
  end

  def handle_info({:stdout, os_pid1, wav_data}, state) when os_pid1 == state.os_pid1 do
    Logger.debug("Data arrived (1)")
    filtered_data = filter(wav_data)
    :ok = :exec.send(state.pid2, filtered_data)
    {:noreply, state}
  end

  def handle_info({:DOWN, os_pid1, :process, _, :normal}, state) when os_pid1 == state.os_pid1 do
    Logger.debug("Encoding finished (1)")
    :ok = :exec.send(state.pid2, :eof)
    {:noreply, state}
  end

  def handle_info({:stdout, os_pid2, opus_data}, state) when os_pid2 == state.os_pid2 do
    Logger.debug("Data arrived (2)")

    if state.awaiter == nil do
      {:noreply, %{state | q: :queue.in(opus_data, state.q)}}
    else
      GenServer.reply(state.awaiter, opus_data)
      {:noreply, %{state | awaiter: nil}}
    end
  end

  def handle_info({:DOWN, os_pid2, :process, _, :normal}, state) when os_pid2 == state.os_pid2 do
    Logger.debug("Encoding finished (2)")

    if state.awaiter != nil do
      true = :queue.is_empty(state.q)
      cast_stop(self())
    end

    {:noreply, %{state | finished: true}}
  end

  def handle_call(:opus_data, from, state) do
    case :queue.out(state.q) do
      {:empty, _} when state.finished ->
        cast_stop(self())
        {:noreply, %{state | awaiter: from}}

      {:empty, _} ->
        {:noreply, %{state | awaiter: from}}

      {{:value, data}, q} ->
        {:reply, data, %{state | q: q}}
    end
  end

  #####
  # Internals

  defp send_src(pid, <<head::size(1024)-binary, rest::binary>>) do
    :ok = :exec.send(pid, head)
    send_src(pid, rest)
  end

  defp send_src(pid, head) do
    :ok = :exec.send(pid, head)
    :ok = :exec.send(pid, :eof)
  end

  defp filter(wav_data) do
    # FIXME
    wav_data
  end
end
