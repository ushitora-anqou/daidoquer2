defmodule Daidoquer2.DiscordEventConsumer do
  use Nostrum.Consumer

  require Logger

  alias Daidoquer2.Guild, as: G

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, %{author: %{bot: true}} = _msg, _ws_state}) do
    # Don't respond to bots
    :ignore
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    name = guild_name(msg.guild_id)

    case Regex.run(~r/^!ddq2?\s+(.+)$/, msg.content) do
      nil ->
        G.cast_message(name, msg)

      [_, "join"] ->
        Daidoquer2.GuildSupSup.add_guild(msg.guild_id)
        G.join_channel(name, msg)

      [_, "leave"] ->
        G.leave_channel(name, msg)

      # FIXME: We probably need "!ddq help"

      _ ->
        # Just ignore "!ddq invalid-command"
        nil
    end
  end

  def handle_event(
        {:VOICE_SPEAKING_UPDATE,
         %Nostrum.Struct.Event.SpeakingUpdate{guild_id: guild_id, speaking: false}, _}
      ) do
    G.notify_speaking_ended(guild_name(guild_id))
  end

  def handle_event({:VOICE_STATE_UPDATE, state, _}) do
    G.notify_voice_state_updated(guild_name(state.guild_id), state)
  end

  def handle_event({:VOICE_READY, state, _}) do
    G.notify_voice_ready(guild_name(state.guild_id), state)
  end

  def handle_event({:THREAD_CREATE, channel, _}) do
    G.thread_create(guild_name(channel.guild_id), channel)
  end

  def handle_event(_event) do
    # Logger.debug("DISCORD EVENT: #{inspect(event)}")
    :noop
  end

  defp guild_name(guild_id) do
    {:via, Registry, {Registry.Guild, guild_id}}
  end
end
