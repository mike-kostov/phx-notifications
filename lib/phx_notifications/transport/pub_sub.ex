defmodule PhxNotifications.Transport.PubSub do
  @moduledoc """
  In-app transport. Broadcasts `{:new_notification, notification}` on the recipient's
  topic so a mounted `PhxNotifications.Bell` updates in real time.

  Always delivered implicitly by the delivery strategy; it never needs to be listed in
  `config :phx_notifications, transports: [...]`.
  """

  @behaviour PhxNotifications.Transport

  alias PhxNotifications.Config

  @impl true
  def deliver(notification, _opts \\ []) do
    Phoenix.PubSub.broadcast(
      Config.pubsub(),
      PhxNotifications.topic_for(notification),
      {:new_notification, notification}
    )
  end
end
