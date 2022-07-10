import Config

config :logger, handle_sasl_reports: true

config :nostrum,
  token: System.fetch_env!("DISCORD_TOKEN"),
  num_shards: :auto,
  ffmpeg: System.get_env("FFMPEG_PATH", "/usr/bin/ffmpeg"),
  youtubedl: System.get_env("YOUTUBEDL_PATH", "/usr/bin/youtube-dl"),
  gateway_intents: [
    :guilds,
    # :guild_bans,
    # :guild_emojis,
    # :guild_integrations,
    # :guild_webhooks,
    # :guild_invites,
    :guild_voice_states,
    :guild_messages,
    # :guild_message_reactions,
    # :guild_message_typing,
    # :direct_messages,
    # :direct_message_reactions,
    # :direct_message_typing,
    # :guild_scheduled_events,
    :message_content
  ]

# config :goth, disabled: true

config :daidoquer2,
  default_post_url: "http://localhost:8399",
  uid2chara:
    %{
      # uid1 => {:post, "http://localhost:8399"},
      # uid2 => {:google, 0}
    },
  tmpfile_path: "/tmp/daidoquer2.tmpfile"
