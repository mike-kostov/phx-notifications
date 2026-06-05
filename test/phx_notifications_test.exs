defmodule PhxNotificationsTest do
  use PhxNotifications.DataCase, async: false

  alias PhxNotifications.Notification

  describe "notify/3 and type inference" do
    setup do
      %{user: user_fixture()}
    end

    test "creates an info notification", %{user: user} do
      assert {:ok, n} = PhxNotifications.notify(user, "hello")
      assert n.body == "hello"
      assert n.recipient_id == user.id
      assert n.recipient_type == to_string(PhxNotifications.TestUser)
      assert Notification.type(n) == :info
    end

    test "url makes it a link notification", %{user: user} do
      assert {:ok, n} = PhxNotifications.notify(user, "see this", url: "/things/1")
      assert Notification.type(n) == :link
    end

    test "actions make it an action notification with stringified keys", %{user: user} do
      assert {:ok, n} =
               PhxNotifications.notify(user, "approve?",
                 actions: [%{key: "approve", label: "Approve"}],
                 meta: %{order_id: 42}
               )

      assert Notification.type(n) == :action
      assert [%{"key" => "approve", "label" => "Approve"}] = n.actions
    end

    test "requires a body", %{user: user} do
      assert {:error, changeset} = PhxNotifications.notify(user, nil)
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "raises for an unpersisted recipient" do
      assert_raise ArgumentError, fn ->
        PhxNotifications.notify(%PhxNotifications.TestUser{}, "no id")
      end
    end
  end

  describe "read state" do
    setup do
      %{user: user_fixture()}
    end

    test "unread_count and mark_read", %{user: user} do
      {:ok, n1} = PhxNotifications.notify(user, "one")
      {:ok, _n2} = PhxNotifications.notify(user, "two")
      assert PhxNotifications.unread_count(user) == 2

      assert {:ok, read} = PhxNotifications.mark_read(n1)
      assert read.read_at
      assert PhxNotifications.unread_count(user) == 1
    end

    test "mark_read is idempotent (keeps original timestamp)", %{user: user} do
      {:ok, n} = PhxNotifications.notify(user, "one")
      {:ok, read} = PhxNotifications.mark_read(n)
      {:ok, read_again} = PhxNotifications.mark_read(read)
      assert read.read_at == read_again.read_at
    end

    test "mark_all_read clears everything", %{user: user} do
      for i <- 1..3, do: PhxNotifications.notify(user, "n#{i}")
      assert {:ok, 3} = PhxNotifications.mark_all_read(user)
      assert PhxNotifications.unread_count(user) == 0
    end

    test "counts are scoped per recipient", %{user: user} do
      other = user_fixture()
      PhxNotifications.notify(user, "mine")
      assert PhxNotifications.unread_count(other) == 0
    end
  end

  describe "list/2" do
    test "returns newest first, respects limit" do
      user = user_fixture()
      for i <- 1..5, do: PhxNotifications.notify(user, "n#{i}")

      bodies = user |> PhxNotifications.list(limit: 3) |> Enum.map(& &1.body)
      assert bodies == ["n5", "n4", "n3"]
    end
  end

  describe "execute_action/3" do
    setup do
      {:ok, n} =
        PhxNotifications.notify(user_fixture(), "approve?",
          actions: [%{key: "approve", label: "Approve"}],
          meta: %{order_id: 7}
        )

      %{notification: n}
    end

    test "runs the handler and marks read on success", %{notification: n} do
      assert {:ok, {:approved, id, %{}}} = PhxNotifications.execute_action(n, "approve")
      assert id == n.id
      assert TestRepo.get!(Notification, n.id).read_at
    end

    test "passes context through", %{notification: n} do
      assert {:ok, {:approved, _, %{from: :endpoint}}} =
               PhxNotifications.execute_action(n, "approve", %{from: :endpoint})
    end

    test "leaves unread and returns error on failure", %{notification: n} do
      assert {:error, :failed} = PhxNotifications.execute_action(n, "boom")
      refute TestRepo.get!(Notification, n.id).read_at
    end

    test "raises on a malformed handler return", %{notification: n} do
      assert_raise ArgumentError, fn -> PhxNotifications.execute_action(n, "bad_return") end
    end
  end

  describe "topics" do
    test "topic/1 and topic_for/1 agree" do
      user = user_fixture()
      {:ok, n} = PhxNotifications.notify(user, "hi")
      assert PhxNotifications.topic(user) == PhxNotifications.topic_for(n)
      assert PhxNotifications.topic(user) =~ "phx_notifications:"
    end
  end
end
