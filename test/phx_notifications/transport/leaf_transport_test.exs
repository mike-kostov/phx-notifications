defmodule PhxNotifications.Transport.LeafTransportTest do
  use PhxNotifications.DataCase, async: false

  alias PhxNotifications.Transport.{Email, Push, SMS}

  setup do
    {:ok, notification} = PhxNotifications.notify(user_fixture(), "hi")
    %{notification: notification}
  end

  defp put_sender(transport_module, sender) do
    Application.put_env(:phx_notifications, transport_module, sender: sender)
    on_exit(fn -> Application.delete_env(:phx_notifications, transport_module) end)
  end

  describe "result-contract normalization (via Email)" do
    test "normalizes :ok and {:ok, _} to :ok", %{notification: n} do
      put_sender(Email, fn _ -> :ok end)
      assert Email.deliver(n) == :ok

      put_sender(Email, fn _ -> {:ok, %{id: "provider-123"}} end)
      assert Email.deliver(n) == :ok
    end

    test "passes through :unavailable (fall back) and :transient (retry)", %{notification: n} do
      put_sender(Email, fn _ -> {:error, :unavailable} end)
      assert Email.deliver(n) == {:error, :unavailable}

      put_sender(Email, fn _ -> {:error, :transient} end)
      assert Email.deliver(n) == {:error, :transient}
    end

    test "classifies unknown errors as :transient", %{notification: n} do
      put_sender(Email, fn _ -> {:error, :some_provider_specific_thing} end)
      assert Email.deliver(n) == {:error, :transient}
    end

    test "catches a raised exception and reports :transient", %{notification: n} do
      put_sender(Email, fn _ -> raise "boom" end)
      assert Email.deliver(n) == {:error, :transient}
    end

    test "raises on a sender that returns garbage", %{notification: n} do
      put_sender(Email, fn _ -> :weird end)
      assert_raise ArgumentError, fn -> Email.deliver(n) end
    end

    test "raises a helpful error when no sender is configured", %{notification: n} do
      Application.delete_env(:phx_notifications, Email)

      assert_raise RuntimeError, ~r/no sender configured for the email transport/, fn ->
        Email.deliver(n)
      end
    end
  end

  describe "the sender receives the notification" do
    test "so it can resolve the destination itself", %{notification: n} do
      test_pid = self()

      put_sender(SMS, fn notification ->
        send(test_pid, {:sent, notification.id})
        :ok
      end)

      assert SMS.deliver(n) == :ok
      assert_receive {:sent, id}
      assert id == n.id
    end

    test "supports an MFA sender", %{notification: n} do
      put_sender(Push, {__MODULE__, :mfa_sender, [self()]})
      assert Push.deliver(n) == :ok
      assert_receive :mfa_called
    end
  end

  test "emits a telemetry event per attempt", %{notification: n} do
    handler = "test-#{System.unique_integer()}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:phx_notifications, :transport, :delivered],
      fn _event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    put_sender(Email, fn _ -> :ok end)
    Email.deliver(n)

    assert_receive {:telemetry, %{duration: _},
                    %{channel: :email, result: :ok, notification_id: id}}

    assert id == n.id
  end

  # MFA target: apply(__MODULE__, :mfa_sender, [notification, test_pid])
  def mfa_sender(_notification, test_pid) do
    send(test_pid, :mfa_called)
    :ok
  end
end
