defmodule Daidoquer2.AudioDirect do
  @behaviour Daidoquer2.GenAudio

  require Logger

  #####
  # External API

  def start_link(src_data) do
    Daidoquer2.GenAudio.start_link(__MODULE__, src_data)
  end

  #####
  # GenAudio callbacks

  def init() do
    Logger.debug("Initialize AudioDirect")
    path = Application.fetch_env!(:daidoquer2, :ffmpeg_path)
    options = Application.fetch_env!(:daidoquer2, :ffmpeg_options_direct) |> List.flatten()
    args = [path | options]
    {:ok, pid, os_pid} = :exec.run(args, [:stdin, :stdout, {:stderr, :print}, :monitor])
    {:ok, pid, %{os_pid: os_pid}}
  end

  def handle_stdout(os_pid, data, state) when os_pid == state.os_pid do
    {:ok, data, state}
  end

  def handle_exit(os_pid, state) when os_pid == state.os_pid do
    {:exit, :normal, state}
  end
end
