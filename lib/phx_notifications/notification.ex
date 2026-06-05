defmodule PhxNotifications.Notification do
  @moduledoc """
  The single notification schema.

  The notification *type* is inferred from which fields are populated rather than
  stored explicitly:

    * has non-empty `actions` ⇒ `:action`
    * else has a non-empty `url` ⇒ `:link`
    * else ⇒ `:info`

  A recipient is identified polymorphically by `recipient_type` (the recipient
  schema module, as a string) plus `recipient_id`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "notifications" do
    field(:recipient_type, :string)
    field(:recipient_id, :integer)
    field(:title, :string)
    field(:body, :string)
    field(:url, :string)
    field(:actions, {:array, :map}, default: [])
    field(:read_at, :utc_datetime_usec)
    field(:meta, :map, default: %{})

    timestamps(type: :utc_datetime_usec)
  end

  @castable [:recipient_type, :recipient_id, :title, :body, :url, :actions, :meta, :read_at]
  @required [:recipient_type, :recipient_id, :body]

  @doc "Changeset for creating/updating a notification."
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, @castable)
    |> validate_required(@required)
  end

  @doc "Marks the notification read, leaving an already-read timestamp untouched."
  def read_changeset(notification) do
    change(notification, read_at: notification.read_at || DateTime.utc_now())
  end

  @doc "Infers the notification type from populated fields."
  @spec type(t()) :: :info | :link | :action
  def type(%__MODULE__{actions: actions}) when is_list(actions) and actions != [], do: :action
  def type(%__MODULE__{url: url}) when is_binary(url) and url != "", do: :link
  def type(%__MODULE__{}), do: :info
end
