defmodule PhxNotifications.Transport do
  @moduledoc """
  Behaviour for *where* a notification goes.

  The default `PhxNotifications.Transport.PubSub` powers the in-app Bell. Out-of-app
  transports (push, email, SMS) implement this same behaviour and are added to
  `config :phx_notifications, transports: [...]`. The caller's `notify/2,3` API never
  changes regardless of which transports are configured.

  ## Result contract

  `deliver/2` must return one of:

    * `:ok` — accepted by the channel/provider.
    * `{:error, :unavailable}` — the recipient cannot be reached this way (no device token,
      no phone number, etc.). A fallback strategy should try the *next* channel.
    * `{:error, :transient}` — a temporary failure (provider 5xx, timeout). The notification
      should be *retried* on the same channel (e.g. by `PhxNotifications.Delivery.Oban`), not
      failed over.

  This three-way distinction is what makes multi-channel fallback/retry correct; see
  `docs/ideas/multi-channel-delivery.md`.
  """

  @type result :: :ok | {:error, :unavailable} | {:error, :transient}

  @doc "Delivers a notification through this transport."
  @callback deliver(notification :: PhxNotifications.Notification.t(), opts :: keyword()) ::
              result()
end
