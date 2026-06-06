defmodule PhxNotifications.Transport.Email do
  @moduledoc """
  Provider-agnostic email transport. Configure a sender; see
  `PhxNotifications.Transport.Sender` for the contract.

      config :phx_notifications, PhxNotifications.Transport.Email,
        sender: &MyApp.Notifications.send_email/1
  """

  @behaviour PhxNotifications.Transport

  @impl true
  def deliver(notification, _opts \\ []) do
    PhxNotifications.Transport.Sender.deliver(:email, __MODULE__, notification)
  end
end
