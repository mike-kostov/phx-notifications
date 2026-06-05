# Compiles only when Plug is available (it is an optional dependency).
if Code.ensure_loaded?(Plug.Conn) do
  defmodule PhxNotifications.Plug.Actions do
    @moduledoc """
    Plug serving out-of-app action links. Mount it in your router:

        forward "/notifications", PhxNotifications.Plug.Actions

    A signed link (see `PhxNotifications.Token`) hits:

        GET /notifications/:id/actions/:action_key?token=<signed>

    The plug verifies the token, runs the action via `PhxNotifications.execute_action/3`,
    marks the notification read, and redirects by precedence:

      1. the action's `redirect_to`
      2. the notification's `url`
      3. `config :phx_notifications, default_redirect: ...` (defaults to `"/"`)
    """

    import Plug.Conn

    alias PhxNotifications.{Config, Notification, Token}

    @behaviour Plug

    @impl true
    def init(opts), do: opts

    @impl true
    def call(%Plug.Conn{path_info: [id, "actions", action_key]} = conn, _opts) do
      conn = fetch_query_params(conn)

      with {:ok, notification} <- fetch_notification(id),
           max_age <- action_max_age(notification, action_key),
           {:ok, %{"notification_id" => nid, "action_key" => key}} <-
             Token.verify(conn.query_params["token"], max_age: max_age),
           true <- to_string(nid) == id and key == action_key do
        run(conn, notification, action_key)
      else
        _ -> respond(conn, 403, "Invalid or expired link")
      end
    end

    def call(conn, _opts), do: respond(conn, 404, "Not found")

    defp run(conn, notification, action_key) do
      case PhxNotifications.execute_action(notification, action_key, %{source: :endpoint}) do
        {:ok, _} -> redirect(conn, redirect_target(notification, action_key))
        {:error, _reason} -> respond(conn, 422, "Action failed")
      end
    end

    defp fetch_notification(id) do
      case Config.repo().get(Notification, id) do
        nil -> {:error, :not_found}
        notification -> {:ok, notification}
      end
    end

    defp action_max_age(notification, action_key) do
      case find_action(notification, action_key) do
        %{"token_max_age" => max_age} when is_integer(max_age) -> max_age
        _ -> Config.action_token_max_age()
      end
    end

    defp redirect_target(notification, action_key) do
      action = find_action(notification, action_key) || %{}
      action["redirect_to"] || notification.url || Config.default_redirect()
    end

    defp find_action(%Notification{actions: actions}, action_key) do
      Enum.find(actions, &(&1["key"] == action_key))
    end

    defp redirect(conn, to) do
      conn
      |> put_resp_header("location", to)
      |> respond(302, "")
    end

    defp respond(conn, status, body) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(status, body)
      |> halt()
    end
  end
end
