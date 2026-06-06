File.mkdir_p!("tmp")

# Start from a clean database file each run.
for ext <- ["", "-shm", "-wal"], do: File.rm("tmp/test.db" <> ext)

children = [
  {Phoenix.PubSub, name: PhxNotifications.PubSub},
  PhxNotifications.TestRepo
]

{:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

Ecto.Migrator.run(
  PhxNotifications.TestRepo,
  [{0, PhxNotifications.TestMigration}, {1, PhxNotifications.TestObanMigration}],
  :up,
  all: true
)

# Oban on the SQLite (Lite) engine, in manual testing mode so jobs are inserted but not run.
{:ok, _} =
  Oban.start_link(
    repo: PhxNotifications.TestRepo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG,
    testing: :manual
  )

ExUnit.start()
