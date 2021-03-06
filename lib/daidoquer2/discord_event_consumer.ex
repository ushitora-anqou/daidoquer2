defmodule Daidoquer2.DiscordEventConsumer do
  use Nostrum.Consumer

  require Logger

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, %{author: %{bot: true}} = _msg, _ws_state}) do
    # Don't respond to bots
    :ignore
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    gid = msg.guild_id

    case Regex.run(~r/^!ddq2?\s+(.+)$/, msg.content) do
      nil ->
        Daidoquer2.GuildRegistry.cast_if_exists(gid, :cast_message, [msg])

      [_, "join"] ->
        Daidoquer2.GuildRegistry.cast(gid, :join_channel, [msg])

      [_, "leave"] ->
        Daidoquer2.GuildRegistry.cast_if_exists(gid, :leave_channel)

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
    Daidoquer2.GuildRegistry.cast_if_exists(guild_id, :notify_speaking_ended)
  end

  def handle_event({:VOICE_STATE_UPDATE, state, _}) do
    Daidoquer2.GuildRegistry.cast_if_exists(state.guild_id, :notify_voice_state_updated, [state])
  end

  def handle_event({:VOICE_READY, state, _}) do
    Daidoquer2.GuildRegistry.cast_if_exists(state.guild_id, :notify_voice_ready, [state])
  end

  def handle_event(event) do
    # Logger.debug("DISCORD EVENT: #{inspect(event)}")
    :noop
  end
end
