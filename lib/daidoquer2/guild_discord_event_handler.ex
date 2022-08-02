defmodule Daidoquer2.GuildDiscordEventHandler do
  require Logger

  alias Daidoquer2.DiscordAPI, as: D
  alias Daidoquer2.GuildSpeaker, as: S

  def thread_create(thread_name, user_name, state) do
    Logger.debug("Thread created (#{state.guild_id}) #{thread_name} by #{user_name}")
    m = voice_template(:created_thread, %{user_name: user_name, thread_name: thread_name})
    S.cast_bare_message(state.speaker, m)
  end

  def i_join(state) do
    Logger.debug("I joined #{state.guild_id}")
    S.cast_enable(state.speaker)
    m = voice_template(:i_joined)
    S.cast_bare_message(state.speaker, m)
  end

  def i_leave(state) do
    Logger.debug("I left #{state.guild_id}")
    S.cast_disable(state.speaker)
  end

  def someone_join(user_id, state) do
    Logger.debug("Someone joined: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    m = voice_template(:joined, %{name: name})
    S.cast_bare_message(state.speaker, m)
  end

  def someone_leave(user_id, state) do
    Logger.debug("Someone left: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    m = voice_template(:left, %{name: name})
    S.cast_bare_message(state.speaker, m)
  end

  def start_streaming(user_id, state) do
    Logger.debug("Someone started streaming: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    m = voice_template(:started_live, %{name: name})
    S.cast_bare_message(state.speaker, m)
  end

  def stop_streaming(user_id, state) do
    Logger.debug("Someone stopped streaming: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    m = voice_template(:stopped_live, %{name: name})
    S.cast_bare_message(state.speaker, m)
  end

  def summon_not_from_vc(msg, _state) do
    # The user doesn't belong to VC
    m = text_template(:summon_not_from_vc)
    text_message(msg, m)
  end

  def summon_but_already_joined(msg, _state) do
    # Already joined
    m = text_template(:summon_but_already_joined)
    text_message(msg, m)
  end

  def summon(msg, vc_id, state) do
    # Really join
    D.join_voice_channel!(state.guild_id, vc_id)
    channel = D.channel!(vc_id)
    m = text_template(:summon, %{channel_name: channel.name})
    text_message(msg, m)
  end

  def unsummon_not_joined(msg, _state) do
    m = text_template(:unsummon_not_joined)
    text_message(msg, m)
  end

  def unsummon_not_from_same_vc(msg, _state) do
    # User does not join the channel
    Logger.debug("'!ddq leave' from another channel")
    m = text_template(:unsummon_not_from_same_vc)
    text_message(msg, m)
  end

  def unsummon(msg, state) do
    vm = voice_template(:im_leaving)
    tm = text_template(:unsummon)

    S.stop_speaking_and_clear_message_queue(state.speaker)
    S.cast_bare_message(state.speaker, vm)
    S.schedule_leave(state.speaker)
    text_message(msg, tm)
  end

  #####
  # Internals

  defp text_message({:message, msg}, text) do
    D.text_message(msg.channel_id, text)
  end

  defp text_message({:interaction, intr}, text) do
    D.text_message_to_interaction(intr, text)
  end

  defp text_template(key, m \\ nil) do
    f =
      Application.fetch_env!(:daidoquer2, :template_text_message)
      |> Map.fetch!(key)

    f.(m)
  end

  defp voice_template(key, m \\ nil) do
    f =
      Application.fetch_env!(:daidoquer2, :template_voice_message)
      |> Map.fetch!(key)

    f.(m)
  end
end
