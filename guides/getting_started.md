# Getting Started

`phx_notifications` gives you in-app notifications — a bell with an unread badge, a dropdown
panel, real-time updates, and action buttons — without hand-rolling the usual PubSub and
read-state plumbing.

## 1. Install

```elixir
# mix.exs
def deps do
  [{:phx_notifications, "~> 0.1.0"}]
end
```

Generate the migration and run it:

```bash
mix phx_notifications.install      # add --binary-id if your user table uses UUIDs
mix ecto.migrate
```

## 2. Configure

```elixir
# config/config.exs
config :phx_notifications,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  action_handler: MyApp.NotificationActions,
  secret_key_base: System.get_env("SECRET_KEY_BASE")  # only needed for action links
```

## 3. Mark a recipient

```elixir
defmodule MyApp.Accounts.User do
  use Ecto.Schema
  use PhxNotifications.Recipient

  schema "users" do
    has_notifications()
    # ...
  end
end
```

## 4. Send notifications

```elixir
# info — cleared only via "Mark all as read"
PhxNotifications.notify(user, "Welcome aboard!")

# link — navigates and marks read on click
PhxNotifications.notify(user, "Your report is ready", url: "/reports/42")

# action — renders buttons handled by your ActionHandler
PhxNotifications.notify(user, "Approve this order?",
  actions: [%{key: "approve", label: "Approve", redirect_to: "/orders/42"}],
  meta: %{order_id: 42}
)
```

Read helpers: `unread_count/1`, `list/2`, `mark_read/1`, `mark_all_read/1`.

## 5. Handle action buttons

One module serves both the in-app Bell click and out-of-app action links:

```elixir
defmodule MyApp.NotificationActions do
  @behaviour PhxNotifications.ActionHandler

  @impl true
  def handle_action("approve", notification, _ctx) do
    MyApp.Orders.approve(notification.meta["order_id"])
    {:ok, :approved}
  end

  def handle_action(_other, _notification, _ctx), do: {:error, :unknown_action}
end
```

Returning `{:ok, _}` marks the notification read; `{:error, reason}` leaves it unread.

## 6. Show the bell

### Example A — default (DaisyUI)

Drop-in, no slots. Works out of the box in a fresh Phoenix app:

```heex
<.live_component module={PhxNotifications.Bell} id="phx_notifications_bell" recipient={@current_user} />
```

For real-time updates, add the hook to the LiveView (a LiveComponent can't receive PubSub
messages on its own):

```elixir
live_session :default, on_mount: [{PhxNotifications.LiveView, recipient_assign: :current_user}] do
  # your live routes
end
```

### Example B — custom trigger and row

A user-to-user notification with the sender's avatar. The `<:trigger>` slot receives the
unread count; the `<:row>` slot receives each notification:

```heex
<.live_component module={PhxNotifications.Bell} id="phx_notifications_bell" recipient={@current_user}>
  <:trigger :let={count}>
    <button class="relative">
      <.icon name="hero-bell" />
      <span :if={count > 0} class="absolute -top-1 -right-1 rounded-full bg-red-500 px-1 text-xs text-white">
        {count}
      </span>
    </button>
  </:trigger>

  <:row :let={n}>
    <div class="flex items-center gap-2">
      <img src={n.meta["avatar_url"]} class="h-8 w-8 rounded-full" alt="" />
      <div>
        <span class="font-medium">{n.meta["sender_name"]}</span>
        <p class="text-sm">{n.body}</p>
      </div>
    </div>
  </:row>
</.live_component>
```

> Note: a custom `<:row>` renders the whole row, so it replaces the default link/action
> button markup. Wire your own `phx-click` handlers if a custom row needs them.

## 7. Out-of-app action links (optional)

Mount the endpoint to let action buttons work from outside the app (e.g. an email link):

```elixir
# router.ex
forward "/notifications", PhxNotifications.Plug.Actions
```

Build a signed link with `PhxNotifications.Token.sign(notification, "approve")` and point it at
`/notifications/:id/actions/approve?token=...`. The endpoint verifies the token, runs the same
`ActionHandler`, marks the notification read, and redirects (action `redirect_to` → notification
`url` → configured `default_redirect`).

Token lifetime defaults to `config :phx_notifications, action_token_max_age: 86_400` and can be
overridden per action with `token_max_age` in the action map (e.g. 30 minutes for a sensitive
action, 30 days for a shared link).
