defmodule PhxNotifications.Delivery.ObanTest do
  use PhxNotifications.DataCase, async: false

  use Oban.Testing,
    repo: PhxNotifications.TestRepo,
    engine: Oban.Engines.Lite,
    notifier: Oban.Notifiers.PG

  alias PhxNotifications.Delivery.Oban, as: ObanDelivery
  alias PhxNotifications.Delivery.Oban.Worker
  alias PhxNotifications.Transport

  setup do
    {:ok, notification} = PhxNotifications.notify(user_fixture(), "hi")
    %{notification: notification}
  end

  defp put_sender(transport_module, sender) do
    Application.put_env(:phx_notifications, transport_module, sender: sender)
    on_exit(fn -> Application.delete_env(:phx_notifications, transport_module) end)
  end

  describe "dispatch/2" do
    test "broadcasts in-app immediately and enqueues a job per out-of-app transport", %{
      notification: n
    } do
      Phoenix.PubSub.subscribe(PhxNotifications.PubSub, PhxNotifications.topic_for(n))

      assert :ok = ObanDelivery.dispatch(n, [Transport.PubSub, Transport.Email, Transport.SMS])

      # In-app is synchronous, not queued.
      assert_receive {:new_notification, received}
      assert received.id == n.id

      # PubSub is never enqueued; the other two are.
      assert_enqueued(
        worker: Worker,
        args: %{"notification_id" => n.id, "transport" => to_string(Transport.Email)}
      )

      assert_enqueued(
        worker: Worker,
        args: %{"notification_id" => n.id, "transport" => to_string(Transport.SMS)}
      )

      refute_enqueued(worker: Worker, args: %{"transport" => to_string(Transport.PubSub)})
    end
  end

  describe "Worker.perform/1 maps the transport contract to Oban semantics" do
    defp job(notification, transport) do
      %Oban.Job{
        args: %{"notification_id" => notification.id, "transport" => to_string(transport)}
      }
    end

    test "ok delivery completes the job", %{notification: n} do
      put_sender(Transport.Email, fn _ -> :ok end)
      assert Worker.perform(job(n, Transport.Email)) == :ok
    end

    test "transient error lets Oban retry", %{notification: n} do
      put_sender(Transport.Email, fn _ -> {:error, :transient} end)
      assert Worker.perform(job(n, Transport.Email)) == {:error, :transient}
    end

    test "unavailable cancels (no retry)", %{notification: n} do
      put_sender(Transport.Email, fn _ -> {:error, :unavailable} end)
      assert Worker.perform(job(n, Transport.Email)) == {:cancel, :unavailable}
    end

    test "a deleted notification cancels rather than retrying forever", %{notification: n} do
      PhxNotifications.TestRepo.delete!(n)
      assert Worker.perform(job(n, Transport.Email)) == {:cancel, :notification_not_found}
    end
  end
end
