defmodule Daidoquer2.CancellableTimer do
  require Logger

  @ets_table ETS.Daidoquer2.Timer

  def init() do
    :ets.new(@ets_table, [:set, :named_table, :public])
  end

  def set_timer(key, time) do
    ref = make_ref()
    Process.send_after(self(), {:timeout, {ref, key}}, time)
    :ets.insert(@ets_table, {ets_key(key), ref})
    Logger.debug("Set timer: #{inspect({key, time, self(), ref})}")
  end

  def cancel_timer(key) do
    :ets.delete(@ets_table, ets_key(key))
    Logger.debug("Cancelled timer: #{inspect({key, self()})}")
  end

  def dispatch({ref, key}, state, module, funname \\ :handle_timeout) do
    case :ets.lookup(@ets_table, ets_key(key)) do
      [{_, ^ref}] ->
        Logger.debug("Dispatch correct timeout: #{inspect({module, ref, key, self()})}")
        :ets.delete(@ets_table, ets_key(key))
        apply(module, funname, [key, state])

      _ ->
        {:noreply, state}
    end
  end

  defp ets_key(key) do
    {self(), key}
  end
end
