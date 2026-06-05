defmodule PhxNotifications.Plug.ActionsTest do
  use PhxNotifications.DataCase, async: false

  import Plug.Test
  import Plug.Conn

  alias PhxNotifications.{Notification, Token}
  alias PhxNotifications.Plug.Actions

  defp action_notification(action_overrides \\ %{}) do
    action = Map.merge(%{key: "approve", label: "Approve"}, action_overrides)
    {:ok, n} = PhxNotifications.notify(user_fixture(), "approve?", actions: [action])
    n
  end

  defp request(id, key, token) do
    Actions.call(conn(:get, "/#{id}/actions/#{key}?token=#{token}"), Actions.init([]))
  end

  test "valid token runs the action, marks read, and redirects to the action's redirect_to" do
    n = action_notification(%{redirect_to: "/done"})
    conn = request(n.id, "approve", Token.sign(n, "approve"))

    assert conn.status == 302
    assert get_resp_header(conn, "location") == ["/done"]
    assert TestRepo.get!(Notification, n.id).read_at
  end

  test "falls back to the notification url, then the default redirect" do
    {:ok, link} =
      PhxNotifications.notify(user_fixture(), "see", url: "/somewhere", actions: [%{key: "go"}])

    conn = request(link.id, "go", Token.sign(link, "go"))
    assert get_resp_header(conn, "location") == ["/somewhere"]
  end

  test "rejects a tampered token / mismatched action" do
    n = action_notification()
    # token signed for "approve" but requested against a different key
    conn = request(n.id, "other", Token.sign(n, "approve"))
    assert conn.status == 403
    refute TestRepo.get!(Notification, n.id).read_at
  end

  test "rejects a missing token" do
    n = action_notification()
    conn = Actions.call(conn(:get, "/#{n.id}/actions/approve"), Actions.init([]))
    assert conn.status == 403
  end

  test "404s for an unknown route shape" do
    conn = Actions.call(conn(:get, "/nonsense"), Actions.init([]))
    assert conn.status == 404
  end

  test "rejects an expired token" do
    n = action_notification(%{token_max_age: -1})
    conn = request(n.id, "approve", Token.sign(n, "approve"))
    assert conn.status == 403
  end
end
