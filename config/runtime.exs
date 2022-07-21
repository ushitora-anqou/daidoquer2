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
  announcer: {:sushikicom, "?speaker=2"},
  dummy_message: "ちくわ大明神。",
  message_length_limit: 100,
  ms_before_join: 0,
  ms_before_leave: 5 * 1000,
  preset_chara: [
    # {:google, 0},
    # {:google, 1},
    # {:google, 2},
    # {:google, 3},
    {:sushikicom, "?speaker=2"},
    {:sushikicom, "?speaker=3"},
    {:sushikicom, "?speaker=8"},
    {:sushikicom, "?speaker=9"},
    {:sushikicom, "?speaker=10"},
    {:sushikicom, "?speaker=11"},
    {:sushikicom, "?speaker=12"},
    {:sushikicom, "?speaker=13"},
    {:sushikicom, "?speaker=14"},
    {:sushikicom, "?speaker=16"},
    {:sushikicom, "?speaker=20"}
  ],
  prompt_regex: ~r/^!ddqa\s+(.+)$/,
  tmpfile_path: "/tmp/daidoquer2.tmpfile",
  uid2chara:
    %{
      # uid1 => {:post, "http://localhost:8399"},
      # uid2 => {:google, 0},
      # uid3 => {:sushikicom, "?speaker=12"},
      # uid4 => {:voicevox_engine, "http://localhost:50021", 0}
    }
