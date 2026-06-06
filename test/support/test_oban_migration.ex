defmodule PhxNotifications.TestObanMigration do
  @moduledoc false
  use Ecto.Migration

  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end
