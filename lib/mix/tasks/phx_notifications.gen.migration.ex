defmodule Mix.Tasks.PhxNotifications.Gen.Migration do
  @shortdoc "Generates the phx_notifications migration"

  @moduledoc """
  Generates a migration that creates the `notifications` table.

      mix phx_notifications.gen.migration

  Options:

    * `--binary-id` — use UUID primary/foreign keys (match your app's user table)
    * `-r`, `--repo` — the Ecto repo (defaults to the app's configured repo)
    * `--migrations-path` — target directory (defaults to the repo's migrations path)
  """

  use Mix.Task

  @switches [binary_id: :boolean, migrations_path: :string, repo: [:string, :keep]]

  @impl true
  def run(args) do
    Mix.Task.run("app.config")
    {opts, _, _} = OptionParser.parse(args, switches: @switches, aliases: [r: :repo])

    repo = repo!(args)
    path = opts[:migrations_path] || Ecto.Migrator.migrations_path(repo)
    Mix.Generator.create_directory(path)

    file = Path.join(path, "#{timestamp()}_create_phx_notifications.exs")
    Mix.Generator.create_file(file, migration_source(repo, binary_id: opts[:binary_id] || false))

    file
  end

  @doc false
  def migration_source(repo, opts) do
    binary_id? = Keyword.get(opts, :binary_id, false)
    module = Module.concat([repo, Migrations, CreatePhxNotifications])

    """
    defmodule #{inspect(module)} do
      use Ecto.Migration

      def change do
        PhxNotifications.Migration.change(binary_id: #{binary_id?})
      end
    end
    """
  end

  defp repo!(args) do
    case Mix.Ecto.parse_repo(args) do
      [repo | _] -> repo
      [] -> Mix.raise("no ecto repo found. Configure :ecto_repos or pass -r MyApp.Repo")
    end
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: "0#{i}"
  defp pad(i), do: to_string(i)
end
