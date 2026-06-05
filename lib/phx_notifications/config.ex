defmodule PhxNotifications.Config do
  @moduledoc """
  Reads `phx_notifications` application configuration.

      config :phx_notifications,
        repo: MyApp.Repo,
        pubsub: MyApp.PubSub,
        action_handler: MyApp.NotificationActions,
        transports: [PhxNotifications.Transport.PubSub],
        delivery: PhxNotifications.Delivery.Inline,
        action_token_max_age: 86_400
  """

  @default_token_max_age 86_400

  @doc "The host application's Ecto repo. Required."
  def repo, do: fetch!(:repo)

  @doc "The host application's `Phoenix.PubSub` server name. Required for in-app delivery."
  def pubsub, do: fetch!(:pubsub)

  @doc "Extra out-of-app transports. PubSub is delivered implicitly and need not be listed."
  def transports, do: get(:transports, [])

  @doc "The delivery strategy module. Defaults to inline `Task` delivery."
  def delivery, do: get(:delivery, PhxNotifications.Delivery.Inline)

  @doc "The configured `PhxNotifications.ActionHandler` module, or nil."
  def action_handler, do: get(:action_handler)

  @doc "Default action-token max age in seconds. Overridable per action."
  def action_token_max_age, do: get(:action_token_max_age, @default_token_max_age)

  @doc "Secret used to sign action-link tokens. Required for the action endpoint."
  def secret_key_base, do: fetch!(:secret_key_base)

  @doc "Fallback redirect target after an out-of-app action when nothing else applies."
  def default_redirect, do: get(:default_redirect, "/")

  defp get(key, default \\ nil), do: Application.get_env(:phx_notifications, key, default)

  defp fetch!(key) do
    get(key) ||
      raise """
      missing required configuration `#{inspect(key)}` for :phx_notifications.

          config :phx_notifications, #{key}: ...
      """
  end
end
