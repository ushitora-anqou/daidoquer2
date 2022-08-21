defmodule Daidoquer2.AudioFiltered do
  @behaviour Daidoquer2.GenAudio

  require Logger

  #####
  # External API

  def start_link(src_data) do
    Daidoquer2.GenAudio.start_link(__MODULE__, src_data)
  end

  def enable_low_voice(pid) do
    Daidoquer2.GenAudio.cast(pid, {:low_voice, true})
  end

  def disable_low_voice(pid) do
    Daidoquer2.GenAudio.cast(pid, {:low_voice, false})
  end

  #####
  # GenAudio callbacks

  def init() do
    Logger.debug("Initialize AudioFiltered")
    path = Application.fetch_env!(:daidoquer2, :ffmpeg_path)
    options1 = Application.fetch_env!(:daidoquer2, :ffmpeg_options1) |> List.flatten()
    options2 = Application.fetch_env!(:daidoquer2, :ffmpeg_options2) |> List.flatten()
    args1 = [path | options1]
    args2 = [path | options2]
    {:ok, pid1, os_pid1} = :exec.run(args1, [:stdin, :stdout, {:stderr, :print}, :monitor])
    {:ok, pid2, os_pid2} = :exec.run(args2, [:stdin, :stdout, {:stderr, :print}, :monitor])

    {:ok, pid1,
     %{
       pid1: pid1,
       pid2: pid2,
       os_pid1: os_pid1,
       os_pid2: os_pid2,
       low_voice: false,
       rest_wav: <<>>
     }}
  end

  def handle_stdout(os_pid, wav_data, state) when os_pid == state.os_pid1 do
    {filtered_data, state} = filter(wav_data, state)
    :ok = :exec.send(state.pid2, filtered_data)
    {:ok, state}
  end

  def handle_stdout(os_pid, opus_data, state) when os_pid == state.os_pid2 do
    {:ok, opus_data, state}
  end

  def handle_exit(os_pid, state) when os_pid == state.os_pid1 do
    :ok = :exec.send(state.pid2, :eof)
    {:ok, state}
  end

  def handle_exit(os_pid, state) when os_pid == state.os_pid2 do
    {:exit, :normal, state}
  end

  def handle_cast({:low_voice, enabled}, state) do
    {:noreply, %{state | low_voice: enabled}}
  end

  #####
  # Internals

  defp filter(wav_data, state) do
    wav_data = state.rest_wav <> wav_data

    if state.low_voice do
      scale = Application.fetch_env!(:daidoquer2, :low_voice_scale)
      {:ok, filtered, rest} = Daidoquer2.VolumeFilter.filter(wav_data, scale)
      {filtered, %{state | rest_wav: rest}}
    else
      {wav_data, %{state | rest_wav: <<>>}}
    end
  end
end
