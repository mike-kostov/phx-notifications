defmodule PhxNotifications.Recipient do
  @moduledoc """
  Mixin for the host application's recipient schema (usually `User`).

      defmodule MyApp.User do
        use Ecto.Schema
        use PhxNotifications.Recipient

        schema "users" do
          has_notifications()
          # ...
        end
      end

  `has_notifications/0,1` defines the `has_many :notifications` association keyed
  on `recipient_id`. Pass `name:` to rename the association.
  """

  defmacro __using__(_opts) do
    quote do
      import PhxNotifications.Recipient, only: [has_notifications: 0, has_notifications: 1]
    end
  end

  @doc "Defines the notifications association on the recipient schema."
  defmacro has_notifications(opts \\ []) do
    name = Keyword.get(opts, :name, :notifications)

    quote do
      Ecto.Schema.has_many(unquote(name), PhxNotifications.Notification,
        foreign_key: :recipient_id
      )
    end
  end
end
