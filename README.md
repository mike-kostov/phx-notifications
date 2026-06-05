# PhxNotifications

A drop-in, self-contained in-app notification system for Phoenix: bell icon, unread
counts, PubSub wiring, and read-state handling out of the box.

Elixir-first, Phoenix-optional — the core needs only Ecto + PubSub; the Bell
LiveComponent and out-of-app transports are optional add-ons.

> Status: **core implemented** (schema, context, transport/delivery/action behaviours).
> Bell LiveComponent and the action endpoint are in progress — see
> [`docs/plans/phoenix-notifications.md`](docs/plans/phoenix-notifications.md).

## Installation

```elixir
def deps do
  [
    {:phx_notifications, "~> 0.1.0"}
  ]
end
```

## Configuration

```elixir
config :phx_notifications,
  repo: MyApp.Repo,
  pubsub: MyApp.PubSub,
  action_handler: MyApp.NotificationActions
```

## Usage

Add the mixin to your recipient schema:

```elixir
defmodule MyApp.User do
  use Ecto.Schema
  use PhxNotifications.Recipient

  schema "users" do
    has_notifications()
    # ...
  end
end
```

Send and read notifications:

```elixir
# info
PhxNotifications.notify(user, "Welcome aboard!")

# link (navigates + marks read on click)
PhxNotifications.notify(user, "Your report is ready", url: "/reports/42")

# action (runs a handler via PhxNotifications.ActionHandler)
PhxNotifications.notify(user, "Approve this order?",
  actions: [%{key: "approve", label: "Approve"}],
  meta: %{order_id: 42}
)

PhxNotifications.unread_count(user)
PhxNotifications.list(user, limit: 20)
PhxNotifications.mark_all_read(user)
```

## Architecture

- **Transports** (*where* a notification goes) — `PhxNotifications.Transport` behaviour;
  `PubSub` ships and drives the in-app Bell. Push/email/SMS are opt-in.
- **Delivery** (*how* it runs) — `PhxNotifications.Delivery` behaviour; `Inline` ships,
  `Oban` is an opt-in upgrade for retries/at-least-once.
- **Actions** — a single configured `PhxNotifications.ActionHandler` runs button logic for
  both the in-app Bell and out-of-app links.

See the design docs in [`docs/`](docs/) for the full rationale.
