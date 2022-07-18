defmodule Daidoquer2.CheckSjis do
  @on_load :load_nifs

  def load_nifs do
    :erlang.load_nif('priv/check_sjis', 0)
  end

  def codepoint(a) do
    raise "NIF check_sjis/1 not implemented"
  end
end
