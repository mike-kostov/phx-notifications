defmodule PhxNotifications.Delivery do
  @moduledoc """
  Behaviour for *how* delivery runs (a different axis from `PhxNotifications.Transport`,
  which is *where* it goes).

    * `PhxNotifications.Delivery.Inline` (default) — broadcast immediately, run extra
      transports in a `Task`.
    * `PhxNotifications.Delivery.Oban` (opt-in, requires Oban) — enqueue a delivery job
      per notification for retries / backoff / at-least-once.
  """

  @doc "Dispatches a freshly-inserted notification across the given extra transports."
  @callback dispatch(notification :: PhxNotifications.Notification.t(), transports :: [module()]) ::
              :ok
end
