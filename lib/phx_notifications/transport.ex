defmodule PhxNotifications.Transport do
  @moduledoc """
  Behaviour for *where* a notification goes.

  The default `PhxNotifications.Transport.PubSub` powers the in-app Bell. Out-of-app
  transports (push, email, SMS) implement this same behaviour and are added to
  `config :phx_notifications, transports: [...]`. The caller's `notify/2,3` API never
  changes regardless of which transports are configured.
  """

  @doc "Delivers a notification through this transport."
  @callback deliver(notification :: PhxNotifications.Notification.t(), opts :: keyword()) ::
              :ok | {:error, term()}
end
