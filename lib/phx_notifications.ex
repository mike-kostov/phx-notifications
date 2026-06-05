defmodule PhxNotifications do
  @moduledoc """
  Drop-in, self-contained in-app notifications for Phoenix.

  Public API:

    * `notify/3` — create and deliver a notification
    * `list/2`, `unread_count/1` — read state
    * `mark_read/1`, `mark_all_read/1` — clear state
    * `execute_action/3` — run an action button's handler (used by the Bell and the
      out-of-app action endpoint)

  See `PhxNotifications.Config` for configuration and `PhxNotifications.Recipient` for
  the schema mixin.
  """

  import Ecto.Query

  alias PhxNotifications.{Config, Notification}

  @type recipient :: struct()

  @doc """
  Creates and delivers a notification to `recipient`.

  Options:

    * `:title` — optional heading
    * `:url` — makes it a link notification (navigates + marks read on click)
    * `:actions` — list of action maps (`%{"key" => ..., "label" => ...}`), makes it an
      action notification
    * `:meta` — caller passthrough data, JSON-safe (e.g. `%{"order_id" => 42}`)
  """
  @spec notify(recipient(), String.t(), keyword()) ::
          {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def notify(recipient, body, opts \\ []) do
    {type, id} = recipient_identity(recipient)

    attrs = %{
      recipient_type: type,
      recipient_id: id,
      body: body,
      title: opts[:title],
      url: opts[:url],
      actions: normalize_actions(opts[:actions]),
      meta: opts[:meta] || %{}
    }

    with {:ok, notification} <-
           Config.repo().insert(Notification.changeset(%Notification{}, attrs)) do
      Config.delivery().dispatch(notification, Config.transports())
      {:ok, notification}
    end
  end

  @doc """
  Lists a recipient's notifications, newest first.

  Options: `:limit` (default 20), `:before` (a `%DateTime{}` for cursor pagination).
  """
  @spec list(recipient(), keyword()) :: [Notification.t()]
  def list(recipient, opts \\ []) do
    {type, id} = recipient_identity(recipient)
    limit = opts[:limit] || 20

    Notification
    |> for_recipient(type, id)
    |> maybe_before(opts[:before])
    |> order_by([n], desc: n.inserted_at, desc: n.id)
    |> limit(^limit)
    |> Config.repo().all()
  end

  @doc "Counts a recipient's unread notifications."
  @spec unread_count(recipient()) :: non_neg_integer()
  def unread_count(recipient) do
    {type, id} = recipient_identity(recipient)

    Notification
    |> for_recipient(type, id)
    |> where([n], is_nil(n.read_at))
    |> Config.repo().aggregate(:count)
  end

  @doc "Marks a single notification read (idempotent)."
  @spec mark_read(Notification.t()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}
  def mark_read(%Notification{} = notification) do
    notification
    |> Notification.read_changeset()
    |> Config.repo().update()
  end

  @doc "Marks all of a recipient's unread notifications read. Returns the count updated."
  @spec mark_all_read(recipient()) :: {:ok, non_neg_integer()}
  def mark_all_read(recipient) do
    {type, id} = recipient_identity(recipient)
    now = DateTime.utc_now()

    {count, _} =
      Notification
      |> for_recipient(type, id)
      |> where([n], is_nil(n.read_at))
      |> Config.repo().update_all(set: [read_at: now, updated_at: now])

    {:ok, count}
  end

  @doc """
  Runs the handler for `action_key` against `notification` via the configured
  `PhxNotifications.ActionHandler`. On `{:ok, _}` the notification is marked read.

  Called by both the Bell LiveComponent and the out-of-app action endpoint.
  """
  @spec execute_action(Notification.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def execute_action(%Notification{} = notification, action_key, context \\ %{}) do
    handler =
      Config.action_handler() ||
        raise """
        no action_handler configured. Action notifications require:

            config :phx_notifications, action_handler: MyApp.NotificationActions
        """

    case handler.handle_action(action_key, notification, context) do
      {:ok, result} ->
        {:ok, _} = mark_read(notification)
        {:ok, result}

      {:error, reason} ->
        {:error, reason}

      other ->
        raise ArgumentError,
              "#{inspect(handler)}.handle_action/3 must return {:ok, _} | {:error, _}, " <>
                "got: #{inspect(other)}"
    end
  end

  @doc "Infers a notification's type (`:info | :link | :action`)."
  defdelegate type(notification), to: Notification

  @doc "The PubSub topic for a recipient (used by the Bell to subscribe)."
  @spec topic(recipient()) :: String.t()
  def topic(recipient) do
    {type, id} = recipient_identity(recipient)
    build_topic(type, id)
  end

  @doc "The PubSub topic a notification will be broadcast on."
  @spec topic_for(Notification.t()) :: String.t()
  def topic_for(%Notification{recipient_type: type, recipient_id: id}), do: build_topic(type, id)

  # --- internal ---

  @doc false
  def recipient_identity(%mod{id: id}) when not is_nil(id), do: {to_string(mod), id}

  def recipient_identity(other) do
    raise ArgumentError,
          "expected a persisted recipient struct with an :id, got: #{inspect(other)}"
  end

  defp build_topic(type, id), do: "phx_notifications:#{type}:#{id}"

  defp for_recipient(query, type, id) do
    where(query, [n], n.recipient_type == ^type and n.recipient_id == ^id)
  end

  defp maybe_before(query, nil), do: query
  defp maybe_before(query, %DateTime{} = before), do: where(query, [n], n.inserted_at < ^before)

  defp normalize_actions(nil), do: []
  defp normalize_actions(actions) when is_list(actions), do: Enum.map(actions, &stringify_keys/1)

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end
end
