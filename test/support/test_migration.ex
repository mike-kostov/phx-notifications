defmodule PhxNotifications.TestMigration do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:name, :string)
      timestamps(type: :utc_datetime_usec)
    end

    # Dogfood the shipped migration body for the notifications table.
    PhxNotifications.Migration.change()
  end
end
