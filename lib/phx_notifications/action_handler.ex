defmodule PhxNotifications.ActionHandler do
  @moduledoc """
  Behaviour the host app implements to run notification action-button logic.

  A single configured handler serves *both* execution paths — the in-app Bell click and
  the out-of-app token endpoint (e.g. an email link, where no LiveView exists). This is
  why action logic lives in a configured module rather than a per-component closure
  (unavailable to the endpoint) or an MFA stored in the DB (refactor-fragile).

      config :phx_notifications, action_handler: MyApp.NotificationActions

      defmodule MyApp.NotificationActions do
        @behaviour PhxNotifications.ActionHandler

        @impl true
        def handle_action("approve", notification, _ctx) do
          MyApp.Orders.approve(notification.meta["order_id"])
          {:ok, :approved}
        end
      end

  Action-specific data should travel in `notification.meta` (JSON-safe), keyed off the
  `action_key`.
  """

  @doc """
  Runs the action identified by `action_key`. Returning `{:ok, _}` marks the notification
  read; `{:error, reason}` leaves it unread and surfaces the error to the caller.
  """
  @callback handle_action(
              action_key :: String.t(),
              notification :: PhxNotifications.Notification.t(),
              context :: map()
            ) :: {:ok, term()} | {:error, term()}
end
