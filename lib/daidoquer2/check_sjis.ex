defmodule Daidoquer2.CheckSjis do
  @on_load :load_nifs

  def load_nifs do
    path = Path.join(:code.priv_dir(:daidoquer2), "check_sjis")
    :erlang.load_nif(path, 0)
  end

  def codepoint(a) do
    raise "NIF check_sjis/1 not implemented"
  end
end
