defmodule PhxNotifications.Transport.Sender do
  @moduledoc """
  Shared implementation for the provider-agnostic leaf transports
  (`PhxNotifications.Transport.Email`, `.SMS`, `.Push`).

  Each leaf transport delegates here. The library ships no provider integration: you configure
  a **sender** per channel and it does the actual sending. The sender receives the
  `%PhxNotifications.Notification{}` (which carries `recipient_id`, `recipient_type`, and `meta`)
  and is responsible for resolving the destination address and sending it.

      config :phx_notifications, PhxNotifications.Transport.Email,
        sender: &MyApp.Notifications.send_email/1

      # or an MFA, called as apply(mod, fun, [notification | extra_args])
      config :phx_notifications, PhxNotifications.Transport.SMS,
        sender: {MyApp.SMS, :deliver, []}

  The sender must return a value this module can normalize into the
  `t:PhxNotifications.Transport.result/0` contract:

    * `:ok` or `{:ok, _}` → `:ok`
    * `{:error, :unavailable}` → `{:error, :unavailable}` (fall back to the next channel)
    * `{:error, :transient}` → `{:error, :transient}` (retry this channel)
    * `{:error, _other}` → treated as `{:error, :transient}` (logged; classify explicitly to avoid this)

  A raised exception is caught, logged, and reported as `{:error, :transient}` so one channel can
  never crash delivery. A `[:phx_notifications, :transport, :delivered]` telemetry event is emitted
  for every attempt.
  """

  require Logger

  alias PhxNotifications.Notification

  @doc false
  @spec deliver(atom(), module(), Notification.t()) :: PhxNotifications.Transport.result()
  def deliver(channel, transport_module, %Notification{} = notification) do
    sender = fetch_sender!(channel, transport_module)
    start = System.monotonic_time()

    # Rescue only the sender invocation (a crash mid-send is transient). Normalization runs
    # outside the rescue so a sender returning a garbage shape surfaces as a loud programmer
    # error rather than being silently swallowed as :transient.
    result =
      case invoke_safely(sender, notification, channel) do
        {:sent, raw} -> normalize(raw)
        :crashed -> {:error, :transient}
      end

    :telemetry.execute(
      [:phx_notifications, :transport, :delivered],
      %{duration: System.monotonic_time() - start},
      %{channel: channel, notification_id: notification.id, result: tag(result)}
    )

    log(channel, notification, result)
    result
  end

  defp invoke_safely(sender, notification, channel) do
    {:sent, invoke(sender, notification)}
  rescue
    error ->
      Logger.error(
        "phx_notifications: #{channel} transport crashed for notification " <>
          "#{notification.id}: #{Exception.message(error)}"
      )

      :crashed
  end

  defp invoke(fun, notification) when is_function(fun, 1), do: fun.(notification)
  defp invoke({mod, fun, args}, notification), do: apply(mod, fun, [notification | args])

  defp normalize(:ok), do: :ok
  defp normalize({:ok, _}), do: :ok
  defp normalize({:error, :unavailable}), do: {:error, :unavailable}
  defp normalize({:error, :transient}), do: {:error, :transient}
  defp normalize({:error, _other}), do: {:error, :transient}

  defp normalize(other) do
    raise ArgumentError,
          "transport sender must return :ok | {:ok, term} | {:error, :unavailable | :transient | term}, " <>
            "got: #{inspect(other)}"
  end

  defp tag(:ok), do: :ok
  defp tag({:error, reason}), do: reason

  defp log(_channel, _notification, :ok), do: :ok

  defp log(channel, notification, {:error, reason}) do
    Logger.warning(
      "phx_notifications: #{channel} delivery of notification #{notification.id} returned #{reason}"
    )
  end

  defp fetch_sender!(channel, transport_module) do
    config = Application.get_env(:phx_notifications, transport_module, [])

    config[:sender] ||
      raise """
      no sender configured for the #{channel} transport. Add:

          config :phx_notifications, #{inspect(transport_module)},
            sender: &MyApp.send_#{channel}/1
      """
  end
end
