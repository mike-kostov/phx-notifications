defmodule PhxNotifications.Transport.Fallback do
  @moduledoc """
  A composite `PhxNotifications.Transport` that tries an ordered list of transports until one
  accepts the notification. Because it *is* a transport, it composes with everything above it
  (delivery strategies, the `transports` config) with no new concepts.

      config :phx_notifications, transports: [PhxNotifications.Transport.Fallback]

      config :phx_notifications, PhxNotifications.Transport.Fallback,
        transports: [
          PhxNotifications.Transport.Push,
          PhxNotifications.Transport.SMS,
          PhxNotifications.Transport.Email
        ]

  ## Semantics (the result contract walked over a chain)

    * The first transport returning `:ok` wins; later transports are not tried.
    * `{:error, :unavailable}` skips to the next transport (this channel can't reach the user).
    * `{:error, :transient}` also moves to the next transport (don't let a temporarily-down
      channel block a working one), but is remembered.
    * If the chain is exhausted with no success: returns `{:error, :transient}` when any channel
      was transiently down (so a retrying strategy like `Delivery.Oban` will try the whole chain
      again), otherwise `{:error, :unavailable}` (genuinely unreachable — don't retry).

  A `[:phx_notifications, :transport, :fallback]` telemetry event is emitted per attempt with the
  winning transport (`delivered_by`) and result.
  """

  @behaviour PhxNotifications.Transport

  @impl true
  def deliver(notification, opts \\ []) do
    transports = fetch_transports!(opts)
    {result, delivered_by} = attempt(transports, notification, false)

    :telemetry.execute(
      [:phx_notifications, :transport, :fallback],
      %{},
      %{notification_id: notification.id, result: tag(result), delivered_by: delivered_by}
    )

    result
  end

  # Returns {result, delivered_by}.
  defp attempt([], _notification, saw_transient?) do
    if saw_transient?, do: {{:error, :transient}, nil}, else: {{:error, :unavailable}, nil}
  end

  defp attempt([transport | rest], notification, saw_transient?) do
    case transport.deliver(notification, []) do
      :ok -> {:ok, transport}
      {:error, :unavailable} -> attempt(rest, notification, saw_transient?)
      {:error, :transient} -> attempt(rest, notification, true)
    end
  end

  defp tag(:ok), do: :ok
  defp tag({:error, reason}), do: reason

  defp fetch_transports!(opts) do
    transports =
      opts[:transports] ||
        Application.get_env(:phx_notifications, __MODULE__, [])[:transports] || []

    case transports do
      [] ->
        raise ArgumentError,
              """
              #{inspect(__MODULE__)} requires a non-empty ordered :transports list. Configure it:

                  config :phx_notifications, #{inspect(__MODULE__)},
                    transports: [PhxNotifications.Transport.Push, PhxNotifications.Transport.Email]
              """

      list ->
        list
    end
  end
end
