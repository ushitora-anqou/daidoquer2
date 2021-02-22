import Config

config :logger, handle_sasl_reports: true

config :nostrum,
  token: System.fetch_env!("DISCORD_TOKEN"),
  num_shards: :auto,
  ffmpeg: "/usr/bin/ffmpeg",
  youtubedl: "/usr/bin/youtube-dl"
