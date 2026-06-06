# Compiles only when Oban is available (it is an optional dependency).
if Code.ensure_loaded?(Oban) do
  defmodule PhxNotifications.Delivery.Oban.Worker do
    @moduledoc """
    Oban worker that delivers one notification through one transport. Maps the transport result
    contract onto Oban job semantics:

      * `:ok` → `:ok` (job done)
      * `{:error, :transient}` → `{:error, :transient}` (Oban retries with backoff)
      * `{:error, :unavailable}` → `{:cancel, :unavailable}` (the user can't be reached this way;
        retrying won't help, so stop)

    A deleted notification cancels the job rather than retrying forever.
    """

    use Oban.Worker

    alias PhxNotifications.{Config, Notification}

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"notification_id" => id, "transport" => transport_str}}) do
      transport = String.to_existing_atom(transport_str)

      case Config.repo().get(Notification, id) do
        nil -> {:cancel, :notification_not_found}
        notification -> map_result(transport.deliver(notification, []))
      end
    end

    defp map_result(:ok), do: :ok
    defp map_result({:error, :unavailable}), do: {:cancel, :unavailable}
    defp map_result({:error, :transient}), do: {:error, :transient}
  end
end
