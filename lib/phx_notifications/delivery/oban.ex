# Compiles only when Oban is available (it is an optional dependency).
if Code.ensure_loaded?(Oban) do
  defmodule PhxNotifications.Delivery.Oban do
    @moduledoc """
    Durable delivery strategy backed by Oban. In-app delivery (PubSub) happens immediately;
    each out-of-app transport becomes its own Oban job so channels retry independently with
    backoff and at-least-once semantics.

        config :phx_notifications, delivery: PhxNotifications.Delivery.Oban

        # optional tuning:
        config :phx_notifications, PhxNotifications.Delivery.Oban,
          queue: :notifications,   # default: :default
          max_attempts: 5,         # default: 5
          oban_name: Oban          # default: Oban

    Requires Oban to be configured and running in the host app, with the chosen queue enabled.
    """

    @behaviour PhxNotifications.Delivery

    alias PhxNotifications.Delivery.Oban.Worker
    alias PhxNotifications.Transport

    @impl true
    def dispatch(notification, transports) do
      # In-app delivery is immediate; there's nothing to retry about a PubSub broadcast.
      Transport.PubSub.deliver(notification)

      transports
      |> Enum.reject(&(&1 == Transport.PubSub))
      |> Enum.each(&enqueue(notification, &1))

      :ok
    end

    defp enqueue(notification, transport) do
      %{"notification_id" => notification.id, "transport" => to_string(transport)}
      |> Worker.new(queue: queue(), max_attempts: max_attempts())
      |> then(&Oban.insert(oban_name(), &1))
    end

    defp opts, do: Application.get_env(:phx_notifications, __MODULE__, [])
    defp queue, do: Keyword.get(opts(), :queue, :default)
    defp max_attempts, do: Keyword.get(opts(), :max_attempts, 5)
    defp oban_name, do: Keyword.get(opts(), :oban_name, Oban)
  end
end
