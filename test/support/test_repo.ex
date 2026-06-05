defmodule PhxNotifications.TestRepo do
  use Ecto.Repo,
    otp_app: :phx_notifications,
    adapter: Ecto.Adapters.SQLite3
end
