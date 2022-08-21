defmodule Daidoquer2.GenAudio do
  @callback init() :: {:ok, sink :: pid(), state :: any()}
  @callback handle_stdout(os_pid :: :erlexec.ospid(), data :: any(), state :: any()) ::
              {:ok, new_state :: any()} | {:ok, data :: any(), new_state :: any()}
  @callback handle_exit(os_pid :: :erlexec.ospid(), state :: any()) ::
              {:ok, new_state :: any()} | {:exit, :normal, new_state :: any()}

  use GenServer, restart: :transient

  require Logger

  #####
  # External API

  def start_link(module, src_data) do
    GenServer.start_link(__MODULE__, {module, src_data})
  end

  def cast(pid, event) do
    GenServer.cast(pid, event)
  end

  def cast_stop(pid) do
    GenServer.cast(pid, :stop)
  end

  def call_opus_data(pid) do
    GenServer.call(pid, :opus_data)
  end

  #####
  # GenServer callbacks
  def init({module, src_data}) do
    Logger.debug("Initialize GenAudio")
    {:ok, pid, mod_state} = apply(module, :init, [])
    send_src(pid, src_data)

    {:ok,
     %{
       q: :queue.new(),
       awaiter: nil,
       finished: false,
       module: module,
       mod_state: mod_state
     }}
  end

  def handle_cast(:stop, state) do
    Logger.debug("Audio stopped: #{inspect(state)}")
    if state.awaiter != nil, do: GenServer.reply(state.awaiter, nil)
    {:stop, :normal, state}
  end

  def handle_cast(event, state) do
    case apply(state.module, :handle_cast, [event, state.mod_state]) do
      {:noreply, mod_state} ->
        {:noreply, %{state | mod_state: mod_state}}
        # FIXME: Add support for possible returned values
    end
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

  # FIXME: Add support for forwarding handle_call to state.module

  def handle_info({:stdout, os_pid, data}, state) do
    # stdout from process spawned by erlexec
    case apply(state.module, :handle_stdout, [os_pid, data, state.mod_state]) do
      {:ok, mod_state} ->
        {:noreply, %{state | mod_state: mod_state}}

      {:ok, data, mod_state} when state.awaiter == nil ->
        {:noreply, %{state | mod_state: mod_state, q: :queue.in(data, state.q)}}

      {:ok, data, mod_state} ->
        GenServer.reply(state.awaiter, data)
        {:noreply, %{state | mod_state: mod_state, awaiter: nil}}
    end
  end

  def handle_info({:DOWN, os_pid, :process, _, :normal}, state) do
    # exit of process spawned by erlexec
    case apply(state.module, :handle_exit, [os_pid, state.mod_state]) do
      {:ok, mod_state} ->
        {:noreply, %{state | mod_state: mod_state}}

      {:exit, :normal, mod_state} when state.awaiter != nil ->
        true = :queue.is_empty(state.q)
        cast_stop(self())
        {:noreply, %{state | mod_state: mod_state, finished: true}}

      {:exit, :normal, mod_state} ->
        {:noreply, %{state | mod_state: mod_state, finished: true}}
    end
  end

  # FIXME: Add support for forwarding handle_info to state.module

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
end
