defmodule PhxNotifications.TestActionHandler do
  @moduledoc false
  @behaviour PhxNotifications.ActionHandler

  @impl true
  def handle_action("approve", notification, ctx) do
    {:ok, {:approved, notification.id, ctx}}
  end

  def handle_action("boom", _notification, _ctx), do: {:error, :failed}

  def handle_action("bad_return", _notification, _ctx), do: :not_a_tuple
end
