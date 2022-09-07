defmodule Daidoquer2.DiscordEventConsumer do
  use Nostrum.Consumer

  require Logger

  alias Daidoquer2.Guild, as: G
  alias Daidoquer2.GuildDiscordEventHandler, as: H
  alias Daidoquer2.GuildSpeaker, as: S
  alias Nostrum.Struct.Interaction

  def start_link do
    Consumer.start_link(__MODULE__)
  end

  def handle_event({:READY, _, _}) do
    create_slash_command = Application.fetch_env!(:daidoquer2, :create_slash_command)

    {:ok, _} =
      create_slash_command.(%{
        name: "join",
        description: "join a VC"
      })

    {:ok, _} =
      create_slash_command.(%{
        name: "leave",
        description: "leave the VC"
      })

    {:ok, _} =
      create_slash_command.(%{
        name: "help",
        description: "help"
      })
  end

  def handle_event({:INTERACTION_CREATE, %Interaction{data: %{name: name}} = interaction, _}) do
    ensure_guild(interaction.guild_id)
    handle_interaction(name, interaction)
  end

  def handle_event({:MESSAGE_CREATE, %{author: %{bot: true}} = _msg, _ws_state}) do
    # Don't respond to bots
    :ignore
  end

  def handle_event({:MESSAGE_CREATE, msg, _ws_state}) do
    prompt_regex = Application.fetch_env!(:daidoquer2, :prompt_regex)

    case Regex.run(prompt_regex, msg.content) do
      nil ->
        S.cast_discord_message(S.name(msg.guild_id), msg)

      [_, "join"] ->
        ensure_guild(msg.guild_id)
        G.join_channel(G.name(msg.guild_id), msg)

      [_, "leave"] ->
        ensure_guild(msg.guild_id)
        G.leave_channel(G.name(msg.guild_id), msg)

      [_, "help"] ->
        H.need_help({:message, msg})

      _ ->
        # Just ignore "!ddq invalid-command"
        nil
    end
  end

  def handle_event(
        {:VOICE_SPEAKING_UPDATE,
         %Nostrum.Struct.Event.SpeakingUpdate{guild_id: guild_id, speaking: false}, _}
      ) do
    S.notify_speaking_ended(S.name(guild_id))
  end

  def handle_event({:VOICE_STATE_UPDATE, state, _}) do
    ensure_guild(state.guild_id)
    G.notify_voice_state_updated(G.name(state.guild_id), state)
  end

  def handle_event({:VOICE_READY, state, _}) do
    G.notify_voice_ready(G.name(state.guild_id), state)
  end

  def handle_event({:VOICE_INCOMING_PACKET, _, state}) do
    S.notify_voice_incoming(S.name(state.guild_id))
  end

  def handle_event({:THREAD_CREATE, channel, _}) do
    G.thread_create(G.name(channel.guild_id), channel)
  end

  def handle_event(_event) do
    # Logger.debug("DISCORD EVENT: #{inspect(event)}")
    :noop
  end

  defp handle_interaction("join", interaction) do
    guild_id = interaction.guild_id
    G.join_channel_via_interaction(G.name(guild_id), interaction)
  end

  defp handle_interaction("leave", interaction) do
    guild_id = interaction.guild_id
    G.leave_channel_via_interaction(G.name(guild_id), interaction)
  end

  defp handle_interaction("help", interaction) do
    H.need_help({:interaction, interaction})
  end

  defp ensure_guild(guild_id) do
    Daidoquer2.GuildSupSup.add_guild(guild_id)
  end
end
