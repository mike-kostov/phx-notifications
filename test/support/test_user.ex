defmodule PhxNotifications.TestUser do
  @moduledoc false
  use Ecto.Schema
  use PhxNotifications.Recipient

  schema "users" do
    field(:name, :string)
    has_notifications()
    timestamps(type: :utc_datetime_usec)
  end
end
