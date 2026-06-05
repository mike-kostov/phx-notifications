defmodule Mix.Tasks.PhxNotifications.Gen.MigrationTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.PhxNotifications.Gen.Migration

  test "builds a migration module that delegates to PhxNotifications.Migration" do
    source = Migration.migration_source(MyApp.Repo, binary_id: false)

    assert source =~ "defmodule MyApp.Repo.Migrations.CreatePhxNotifications do"
    assert source =~ "use Ecto.Migration"
    assert source =~ "PhxNotifications.Migration.change(binary_id: false)"
  end

  test "threads the --binary-id option into the generated call" do
    source = Migration.migration_source(MyApp.Repo, binary_id: true)
    assert source =~ "PhxNotifications.Migration.change(binary_id: true)"
  end
end
