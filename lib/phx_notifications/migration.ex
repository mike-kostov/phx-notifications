defmodule PhxNotifications.Migration do
  @moduledoc """
  Shared migration body for the `notifications` table, so the schema definition lives in one
  place. Generated migrations (via `mix phx_notifications.gen.migration`) simply delegate here:

      defmodule MyApp.Repo.Migrations.CreatePhxNotifications do
        use Ecto.Migration

        def change do
          PhxNotifications.Migration.change(binary_id: false)
        end
      end

  Pass `binary_id: true` to use UUID primary/foreign keys (match your app's user table).
  """

  use Ecto.Migration

  @doc "Creates the notifications table and its lookup index."
  def change(opts \\ []) do
    binary_id? = Keyword.get(opts, :binary_id, false)
    recipient_id_type = if binary_id?, do: :binary_id, else: :bigint

    create table(:notifications, primary_key: not binary_id?) do
      if binary_id?, do: add(:id, :binary_id, primary_key: true)

      add(:recipient_type, :string, null: false)
      add(:recipient_id, recipient_id_type, null: false)
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
