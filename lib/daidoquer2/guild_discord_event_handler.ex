defmodule Daidoquer2.GuildDiscordEventHandler do
  require Logger

  alias Daidoquer2.DiscordAPI, as: D
  alias Daidoquer2.GuildSpeaker, as: S

  def thread_create(thread_name, user_name, state) do
    Logger.debug("Thread created (#{state.guild_id}) #{thread_name} by #{user_name}")
    S.cast_bare_message(state.speaker, "#{user_name}さんがスレッド「#{thread_name}」を作りました。")
  end

  def i_join(state) do
    Logger.debug("I joined #{state.guild_id}")
    S.cast_enable(state.speaker)
    S.cast_bare_message(state.speaker, "こんにちは、daidoquer2です。やさしくしてね。")
  end

  def i_leave(state) do
    Logger.debug("I left #{state.guild_id}")
    S.cast_disable(state.speaker)
  end

  def someone_join(user_id, state) do
    Logger.debug("Someone joined: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    S.cast_bare_message(state.speaker, "#{name}さんが参加しました。")
  end

  def someone_leave(user_id, state) do
    Logger.debug("Someone left: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    S.cast_bare_message(state.speaker, "#{name}さんが離れました。")
  end

  def start_streaming(user_id, state) do
    Logger.debug("Someone started streaming: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    S.cast_bare_message(state.speaker, "#{name}さんがライブを始めました。")
  end

  def stop_streaming(user_id, state) do
    Logger.debug("Someone stopped streaming: #{state.guild_id}: uid=#{user_id}")
    name = D.display_name_of_user!(state.guild_id, user_id)
    Logger.debug("Name retrieved: #{state.guild_id}: uid=#{user_id} name=#{name}")

    S.cast_bare_message(state.speaker, "#{name}さんがライブを終了しました。")
  end

  def summon_not_from_vc(msg, _state) do
    # The user doesn't belong to VC
    text_message(msg, "Call from VC")
  end

  def summon_but_already_joined(msg, _state) do
    # Already joined
    text_message(msg, "Already joined")
  end

  def summon(msg, vc_id, state) do
    # Really join
    D.join_voice_channel!(state.guild_id, vc_id)
    channel = D.channel!(vc_id)
    text_message(msg, "Joined #{channel.name}")
  end

  def unsummon_not_from_same_vc(msg, _state) do
    # User does not join the channel
    Logger.debug("'!ddq leave' from another channel")
    text_message(msg, "Call from the same VC channel")
  end

  def unsummon(msg, state) do
    S.stop_speaking_and_clear_message_queue(state.speaker)
    S.cast_bare_message(state.speaker, "。お相手はdaidoquer2でした。またね。")
    S.schedule_leave(state.speaker)
    text_message(msg, "Leaving")
  end

  #####
  # Internals

  defp text_message({:message, msg}, text) do
    D.text_message(msg.channel_id, text)
  end

  defp text_message({:interaction, intr}, text) do
    D.text_message_to_interaction(intr, text)
  end
end
