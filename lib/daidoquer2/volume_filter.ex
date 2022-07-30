defmodule Daidoquer2.VolumeFilter do
  @on_load :load_nifs

  def load_nifs do
    path = Path.join(:code.priv_dir(:daidoquer2), "volume_filter")
    :erlang.load_nif(path, 0)
  end

  def filter(_, _) do
    raise "NIF filter/2 not implemented"
  end
end
