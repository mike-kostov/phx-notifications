defmodule Mix.Tasks.PhxNotifications.Install do
  @shortdoc "Installs phx_notifications: generates the migration and prints setup steps"

  @moduledoc """
  Generates the `notifications` migration and prints the remaining setup steps.

      mix phx_notifications.install

  Accepts the same options as `mix phx_notifications.gen.migration` (e.g. `--binary-id`).
  Run `mix ecto.migrate` afterwards.
  """

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("phx_notifications.gen.migration", args)
    Mix.shell().info(instructions())
  end

  defp instructions do
    """

    phx_notifications: migration generated. Next steps:

      1. Run the migration:

          mix ecto.migrate

      2. Configure the library:

          config :phx_notifications,
            repo: MyApp.Repo,
            pubsub: MyApp.PubSub,
            action_handler: MyApp.NotificationActions,
            secret_key_base: "<at least 64 bytes; used to sign action links>"

      3. Add the mixin to your recipient schema:

          use PhxNotifications.Recipient
          # then, inside `schema`:
          has_notifications()

      4. (Optional) Real-time Bell — add the component to a LiveView and the hook:

          <.live_component module={PhxNotifications.Bell} id="phx_notifications_bell" recipient={@current_user} />
          on_mount {PhxNotifications.LiveView, recipient_assign: :current_user}

      5. (Optional) Out-of-app action links — mount the endpoint in your router:

          forward "/notifications", PhxNotifications.Plug.Actions
    """
  end
end
