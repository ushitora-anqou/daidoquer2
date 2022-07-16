defmodule Daidoquer2.GuildRegistry do
  require Logger

  def set_pid(key, guild_id) do
    try do
      :gproc.reg(gproc_id(key, guild_id))
      :ok
    catch
      e ->
        Logger.error("set_pid: #{key} #{guild_id} failed: #{inspect(e)}")
        {:error, e}
    end
  end

  def apply(key, guild_id, module, funname, args \\ []) do
    if where(key, guild_id) == :undefined do
      {:ok, _} = Daidoquer2.GuildSupervisor.add_speaker(guild_id)
      :gproc.await(gproc_id(:speaker, guild_id))
      {:ok, _} = Daidoquer2.GuildSupervisor.add_guild(guild_id)
      :gproc.await(gproc_id(:guild, guild_id))
    end

    apply_if_exists(key, guild_id, module, funname, args)
  end

  def apply_if_exists(key, guild_id, module, funname, args \\ []) do
    case where(key, guild_id) do
      :undefined ->
        Logger.debug("#{key} #{guild_id} not found")
        {:error, :not_exists}

      pid ->
        apply(module, funname, [pid | args])
    end
  end

  defp where(key, guild_id) do
    :gproc.where(gproc_id(key, guild_id))
  end

  defp gproc_id(key, guild_id) do
    {:n, :l, {:daidoquer2, key, guild_id}}
  end
end
