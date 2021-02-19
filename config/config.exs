import Config

config :logger, handle_sasl_reports: true

config :nostrum,
  token: System.get_env("DISCORD_TOKEN"),
  num_shards: :auto,
  youtubedl: "/home/anqou/workspace/youtube-dl"
