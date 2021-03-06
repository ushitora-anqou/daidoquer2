defmodule Daidoquer2.DiscordAPI do
  alias Nostrum.Api
  alias Nostrum.Voice
  alias Nostrum.Cache.Me
  alias Nostrum.Cache.ChannelCache
  alias Nostrum.Cache.UserCache
  alias Nostrum.Cache.GuildCache

  def me do
    Me.get()
  end

  def text_message(channel_id, message) do
    Api.create_message(channel_id, message)
  end

  def channel(chan_id) do
    case ChannelCache.get(chan_id) do
      {:ok, chan} -> {:ok, chan}
      {:error, _} -> Api.get_channel(chan_id)
    end
  end

  def channel!(chan_id) do
    case ChannelCache.get(chan_id) do
      {:ok, chan} -> chan
      {:error, _} -> Api.get_channel!(chan_id)
    end
  end

  def user!(user_id) do
    case UserCache.get(user_id) do
      {:ok, user} -> user
      {:error, _} -> Api.get_user!(user_id)
    end
  end

  def guild!(guild_id) do
    case GuildCache.get(guild_id) do
      {:ok, user} -> user
      {:error, _} -> Api.get_guild!(guild_id)
    end
  end

  def voice_states_of_guild!(guild_id) do
    guild_id
    |> guild!
    |> Map.get(:voice_states)
  end

  def voice_channel_of_user!(guild_id, user_id) do
    guild_id
    |> voice_states_of_guild!
    |> Enum.find(%{}, fn v -> v.user_id == user_id end)
    |> Map.get(:channel_id)
  end

  def display_name_of_user(guild_id, user_id) do
    # FIXME: Can use GuildCache?
    case Api.get_guild_member(guild_id, user_id) do
      {:ok, member} -> {:ok, member.nick || member.user.username}
      error -> error
    end
  end

  def display_name_of_user!(guild_id, user_id) do
    {:ok, name} = display_name_of_user(guild_id, user_id)
    name
  end

  def num_of_users_in_my_channel!(guild_id) do
    my_channel = voice_channel_of_user!(guild_id, Me.get().id)

    guild_id
    |> voice_states_of_guild!
    |> Enum.filter(fn v ->
      v.channel_id == my_channel and user!(v.user_id).bot != true
    end)
    |> length
  end

  def join_voice_channel!(guild_id, vchannel_id) do
    :ok = Voice.join_channel(guild_id, vchannel_id)
  end

  def leave_voice_channel(guild_id) do
    Voice.leave_channel(guild_id)
  end

  def voice_play!(guild_id, input, type \\ :uri, options \\ []) do
    :ok = Voice.play(guild_id, input, type, options)
  end

  def voice_stop(guild_id) do
    Voice.stop(guild_id)
  end

  def voice_ready?(guild_id) do
    Voice.ready?(guild_id)
  end

  def voice_playing?(guild_id) do
    Voice.playing?(guild_id)
  end
end
