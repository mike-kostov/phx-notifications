defmodule PhxNotifications.Delivery.Inline do
  @moduledoc """
  Default delivery strategy: broadcast in-app immediately, then fan out to any extra
  out-of-app transports in fire-and-forget `Task`s. Sufficient for in-app delivery with
  no extra dependencies.
  """

  @behaviour PhxNotifications.Delivery

  require Logger

  alias PhxNotifications.Transport

  @impl true
  def dispatch(notification, transports) do
    # In-app delivery is synchronous so the Bell updates without a round-trip.
    Transport.PubSub.deliver(notification)

    transports
    |> Enum.reject(&(&1 == Transport.PubSub))
    |> Enum.each(fn transport ->
      Task.start(fn -> safe_deliver(transport, notification) end)
    end)

    :ok
  end

  defp safe_deliver(transport, notification) do
    transport.deliver(notification, [])
  rescue
    error ->
      Logger.error(
        "phx_notifications: #{inspect(transport)} failed to deliver " <>
          "notification #{notification.id}: #{Exception.message(error)}"
      )
  end
end
