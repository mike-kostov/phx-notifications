defmodule PhxNotifications.TestMigration do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:users) do
      add(:name, :string)
      timestamps(type: :utc_datetime_usec)
    end

    create table(:notifications) do
      add(:recipient_type, :string, null: false)
      add(:recipient_id, :bigint, null: false)
      add(:title, :string)
      add(:body, :text, null: false)
      add(:url, :string)
      add(:actions, :map)
      add(:read_at, :utc_datetime_usec)
      add(:meta, :map)
      timestamps(type: :utc_datetime_usec)
    end

    create(index(:notifications, [:recipient_type, :recipient_id]))
  end
end
