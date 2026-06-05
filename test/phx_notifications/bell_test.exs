defmodule PhxNotifications.BellTest do
  use PhxNotifications.DataCase, async: false

  import Phoenix.LiveViewTest

  alias PhxNotifications.Bell

  test "renders the default trigger with an unread badge and loads data" do
    user = user_fixture()
    {:ok, _} = PhxNotifications.notify(user, "hello there")
    {:ok, _} = PhxNotifications.notify(user, "second")

    html = render_component(Bell, id: "bell", recipient: user)

    # Default DaisyUI trigger + unread count badge.
    assert html =~ "btn-circle"
    assert html =~ "indicator-item"
    assert html =~ "2"
  end

  test "renders zero state without a badge" do
    user = user_fixture()
    html = render_component(Bell, id: "bell", recipient: user)
    refute html =~ "indicator-item"
  end
end
