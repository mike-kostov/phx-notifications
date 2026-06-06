defmodule PhxNotifications.Transport.Push do
  @moduledoc """
  Provider-agnostic push transport (FCM/APNS/web push — your choice). Configure a sender; see
  `PhxNotifications.Transport.Sender` for the contract.

      config :phx_notifications, PhxNotifications.Transport.Push,
        sender: &MyApp.Push.deliver/1
  """

  @behaviour PhxNotifications.Transport

  @impl true
  def deliver(notification, _opts \\ []) do
    PhxNotifications.Transport.Sender.deliver(:push, __MODULE__, notification)
  end
end
