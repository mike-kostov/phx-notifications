defmodule PhxNotifications.Token do
  @moduledoc """
  Signs and verifies action-link tokens so action buttons can be triggered from outside the
  app (e.g. a link in an email) without an authenticated session.

  Tokens are signed with `config :phx_notifications, secret_key_base: ...` via `Plug.Crypto`
  and carry the notification id + action key. Expiry is checked at verification time; the
  caller supplies `max_age` from the action's `token_max_age` or the module default.
  """

  alias PhxNotifications.Config

  @salt "phx_notifications action token"

  @doc "Signs a token for `action_key` on `notification`."
  @spec sign(PhxNotifications.Notification.t(), String.t()) :: String.t()
  def sign(notification, action_key) do
    Plug.Crypto.sign(
      Config.secret_key_base(),
      @salt,
      %{"notification_id" => notification.id, "action_key" => action_key}
    )
  end

  @doc """
  Verifies a token. Pass `max_age:` (seconds) to enforce expiry.

  Returns `{:ok, %{"notification_id" => id, "action_key" => key}}` or
  `{:error, :expired | :invalid | :missing}`.
  """
  @spec verify(String.t() | nil, keyword()) :: {:ok, map()} | {:error, atom()}
  def verify(nil, _opts), do: {:error, :missing}

  def verify(token, opts) when is_binary(token) do
    Plug.Crypto.verify(Config.secret_key_base(), @salt, token, opts)
  end
end
