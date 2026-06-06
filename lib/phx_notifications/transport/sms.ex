defmodule PhxNotifications.Transport.SMS do
  @moduledoc """
  Provider-agnostic SMS transport. Configure a sender; see
  `PhxNotifications.Transport.Sender` for the contract.

      config :phx_notifications, PhxNotifications.Transport.SMS,
        sender: {MyApp.SMS, :deliver, []}
  """

  @behaviour PhxNotifications.Transport

  @impl true
  def deliver(notification, _opts \\ []) do
    PhxNotifications.Transport.Sender.deliver(:sms, __MODULE__, notification)
  end
end
