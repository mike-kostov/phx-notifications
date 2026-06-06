defmodule PhxNotifications.Transport.FallbackTest do
  use PhxNotifications.DataCase, async: false

  alias PhxNotifications.Transport.{Email, Fallback, Push, SMS}

  setup do
    {:ok, notification} = PhxNotifications.notify(user_fixture(), "hi")
    %{notification: notification}
  end

  defp put_sender(transport_module, sender) do
    Application.put_env(:phx_notifications, transport_module, sender: sender)
    on_exit(fn -> Application.delete_env(:phx_notifications, transport_module) end)
  end

  defp put_chain(transports) do
    Application.put_env(:phx_notifications, Fallback, transports: transports)
    on_exit(fn -> Application.delete_env(:phx_notifications, Fallback) end)
  end

  # Convenience: a sender that records being called, then returns `result`.
  defp recording(result) do
    test_pid = self()

    fn notification ->
      send(test_pid, {:called, notification.id})
      result
    end
  end

  test "first :ok wins and short-circuits the rest", %{notification: n} do
    put_sender(Email, fn _ -> :ok end)
    put_sender(SMS, recording(:ok))
    put_chain([Email, SMS])

    assert Fallback.deliver(n) == :ok
    refute_receive {:called, _}, 50
  end

  test "skips :unavailable and delivers via the next channel", %{notification: n} do
    put_sender(SMS, fn _ -> {:error, :unavailable} end)
    put_sender(Email, recording(:ok))
    put_chain([SMS, Email])

    assert Fallback.deliver(n) == :ok
    assert_receive {:called, _}
  end

  test "a transient channel does not block a working later channel", %{notification: n} do
    put_sender(Push, fn _ -> {:error, :transient} end)
    put_sender(Email, fn _ -> :ok end)
    put_chain([Push, Email])

    assert Fallback.deliver(n) == :ok
  end

  test "all unavailable -> :unavailable (don't retry)", %{notification: n} do
    put_sender(SMS, fn _ -> {:error, :unavailable} end)
    put_sender(Email, fn _ -> {:error, :unavailable} end)
    put_chain([SMS, Email])

    assert Fallback.deliver(n) == {:error, :unavailable}
  end

  test "exhausted but a channel was transient -> :transient (retry the chain)", %{notification: n} do
    put_sender(SMS, fn _ -> {:error, :unavailable} end)
    put_sender(Push, fn _ -> {:error, :transient} end)
    put_chain([SMS, Push])

    assert Fallback.deliver(n) == {:error, :transient}
  end

  test "raises on an empty / unconfigured chain", %{notification: n} do
    assert_raise ArgumentError, ~r/non-empty ordered :transports/, fn -> Fallback.deliver(n) end
  end

  test "emits a telemetry event naming the delivering transport", %{notification: n} do
    handler = "fallback-#{System.unique_integer()}"
    test_pid = self()

    :telemetry.attach(
      handler,
      [:phx_notifications, :transport, :fallback],
      fn _e, _m, meta, _ -> send(test_pid, {:fallback_telemetry, meta}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    put_sender(SMS, fn _ -> {:error, :unavailable} end)
    put_sender(Email, fn _ -> :ok end)
    put_chain([SMS, Email])

    Fallback.deliver(n)
    assert_receive {:fallback_telemetry, %{result: :ok, delivered_by: Email}}
  end
end
