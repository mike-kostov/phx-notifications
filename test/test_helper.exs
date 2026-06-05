File.mkdir_p!("tmp")

# Start from a clean database file each run.
for ext <- ["", "-shm", "-wal"], do: File.rm("tmp/test.db" <> ext)

children = [
  {Phoenix.PubSub, name: PhxNotifications.PubSub},
  PhxNotifications.TestRepo
]

{:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

Ecto.Migrator.run(PhxNotifications.TestRepo, [{0, PhxNotifications.TestMigration}], :up,
  all: true
)

ExUnit.start()
