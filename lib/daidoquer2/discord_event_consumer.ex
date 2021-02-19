defmodule Daidoquer2.DiscordEventConsumer do
  use Nostrum.Consumer

  require Logger

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    if msg.author.bot do
      # Don't respond to bots
      :ignore
    else
      gid = msg.guild_id

      case msg.content do
        "!ddq2 join" ->
          Daidoquer2.GuildRegistry.cast(gid, :join_channel, [msg])

        "!ddq2 leave" ->
          Daidoquer2.GuildRegistry.cast(gid, :leave_channel)

        _ ->
          Daidoquer2.GuildRegistry.cast(gid, :cast_message, [msg])
      end
    end
  end

  def handle_event(
        {:VOICE_SPEAKING_UPDATE,
         %Nostrum.Struct.Event.SpeakingUpdate{guild_id: guild_id, speaking: false}, _}
      ) do
    Daidoquer2.GuildRegistry.cast(guild_id, :notify_speaking_ended)
  end

  def handle_event({:VOICE_STATE_UPDATE, state, _}) do
    Logger.debug("voice state update #{inspect(state)}")
    Daidoquer2.GuildRegistry.cast(state.guild_id, :notify_voice_state_updated, [state])
  end

  def handle_event(event) do
    Logger.debug(inspect(event))
    :noop
  end
end
