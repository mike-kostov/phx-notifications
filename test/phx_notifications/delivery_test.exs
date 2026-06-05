defmodule PhxNotifications.DeliveryTest do
  use PhxNotifications.DataCase, async: false

  test "notify broadcasts on the recipient topic via the default delivery" do
    user = user_fixture()
    Phoenix.PubSub.subscribe(PhxNotifications.PubSub, PhxNotifications.topic(user))

    {:ok, notification} = PhxNotifications.notify(user, "ping")

    assert_receive {:new_notification, received}
    assert received.id == notification.id
    assert received.body == "ping"
  end

  test "broadcasts are scoped to the recipient topic" do
    user = user_fixture()
    other = user_fixture()
    Phoenix.PubSub.subscribe(PhxNotifications.PubSub, PhxNotifications.topic(other))

    {:ok, _} = PhxNotifications.notify(user, "not for other")

    refute_receive {:new_notification, _}, 100
  end
end
