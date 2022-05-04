import Config

config :logger, handle_sasl_reports: true

config :nostrum,
  token: System.fetch_env!("DISCORD_TOKEN"),
  num_shards: :auto,
  ffmpeg: System.get_env("FFMPEG_PATH", "/usr/bin/ffmpeg"),
  youtubedl: System.get_env("YOUTUBEDL_PATH", "/usr/bin/youtube-dl")

# config :goth, disabled: true

config :daidoquer2,
  default_post_url: "http://localhost:8399",
  uid2chara:
    %{
      # uid1 => {:post, "http://localhost:8399"},
      # uid2 => {:google, 0}
    }
