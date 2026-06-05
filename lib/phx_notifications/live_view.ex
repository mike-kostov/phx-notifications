# Compiles only when Phoenix LiveView is available (it is an optional dependency).
if Code.ensure_loaded?(Phoenix.LiveView) do
  defmodule PhxNotifications.LiveView do
    @moduledoc """
    `on_mount` hook that wires real-time delivery to a `PhxNotifications.Bell`.

    A `LiveComponent` cannot receive PubSub messages directly, so this hook (running in the
    host LiveView process) subscribes to the recipient's topic and forwards each broadcast to
    the Bell via `send_update/3`.

        live_session :default, on_mount: [{PhxNotifications.LiveView, recipient_assign: :current_user}] do
          # ...
        end

    Options:

      * `:recipient_assign` — socket assign holding the recipient struct (default `:current_user`)
      * `:bell_id` — the Bell component id to forward to (default `"phx_notifications_bell"`)
    """

    import Phoenix.LiveView, only: [attach_hook: 4]

    @default_bell_id "phx_notifications_bell"

    def on_mount(opts, _params, _session, socket) do
      opts = if is_list(opts), do: opts, else: []
      recipient_assign = Keyword.get(opts, :recipient_assign, :current_user)
      bell_id = Keyword.get(opts, :bell_id, @default_bell_id)

      socket =
        if Phoenix.LiveView.connected?(socket) do
          maybe_subscribe(socket, Map.get(socket.assigns, recipient_assign), bell_id)
        else
          socket
        end

      {:cont, socket}
    end

    defp maybe_subscribe(socket, nil, _bell_id), do: socket

    defp maybe_subscribe(socket, recipient, bell_id) do
      Phoenix.PubSub.subscribe(
        PhxNotifications.Config.pubsub(),
        PhxNotifications.topic(recipient)
      )

      attach_hook(socket, :phx_notifications, :handle_info, fn
        {:new_notification, notification}, socket ->
          Phoenix.LiveView.send_update(PhxNotifications.Bell,
            id: bell_id,
            new_notification: notification
          )

          {:halt, socket}

        _message, socket ->
          {:cont, socket}
      end)
    end
  end
end
