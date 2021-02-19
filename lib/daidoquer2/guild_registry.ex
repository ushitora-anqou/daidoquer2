defmodule Daidoquer2.GuildRegistry do
  use GenServer

  require Logger

  def start_link(_) do
    GenServer.start_link(__MODULE__, nil, name: __MODULE__)
  end

  def cast(guild_id, funname, args \\ []) do
    case where(guild_id) do
      :undefined ->
        GenServer.cast(__MODULE__, {:create_new_guild_then_cast, guild_id, funname, args})

      pid ->
        apply_guild(pid, funname, args)
    end
  end

  def where(guild_id) do
    :gproc.where(get_gproc_id_for_guild(guild_id))
  end

  def get_gproc_id_for_guild(guild_id) do
    {:n, :l, {:daidoquer2, guild_id}}
  end

  #####
  # GenServer callbacks
  def init(_) do
    {:ok, nil}
  end

  def handle_cast({:create_new_guild_then_cast, guild_id, funname, args}, state) do
    pid =
      case where(guild_id) do
        :undefined ->
          {:ok, pid} = Daidoquer2.GuildSupervisor.add_guild(guild_id)
          :gproc.await(get_gproc_id_for_guild(guild_id))
          pid

        pid ->
          pid
      end

    apply_guild(pid, funname, args)
    {:noreply, state}
  end

  defp apply_guild(pid, funname, args) do
    apply(:"Elixir.Daidoquer2.Guild", funname, [pid | args])
  end
end
