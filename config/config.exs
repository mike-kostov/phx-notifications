import Config

if config_env() == :test do
  config :phx_notifications,
    ecto_repos: [PhxNotifications.TestRepo],
    repo: PhxNotifications.TestRepo,
    pubsub: PhxNotifications.PubSub,
    action_handler: PhxNotifications.TestActionHandler,
    secret_key_base: String.duplicate("a", 64)

  config :phx_notifications, PhxNotifications.TestRepo,
    adapter: Ecto.Adapters.SQLite3,
    database: "tmp/test.db",
    pool_size: 1,
    migration_lock: false

  config :logger, level: :warning
end
