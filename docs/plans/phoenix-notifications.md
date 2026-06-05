# phx_notifications — Implementation Plan

Translates [`docs/ideas/phoenix-notifications.md`](../ideas/phoenix-notifications.md) into a concrete build. Read the idea doc first for the "what and why"; this doc is the "how."

Package: `phx_notifications` · Modules: `PhxNotifications.*` · Initial version: `0.1.0`.
(Local folder stays `phoenix_notifications/` — cosmetic only, nothing derives from it.)

## 1. Schema & migration

Single `notifications` table. Type is inferred from which columns are populated (info / link / action), no explicit `type` column.

| column         | type           | notes                                                        |
| -------------- | -------------- | ------------------------------------------------------------ |
| `id`           | `bigserial`    | PK (or `binary_id` — see open item below)                    |
| `recipient_id` | `bigint`       | FK to the host app's user table; column/type configurable    |
| `body`         | `text`         | required — the message                                       |
| `title`        | `string`       | optional                                                     |
| `url`          | `string`       | optional — presence ⇒ link notification                      |
| `actions`      | `jsonb`        | optional — presence ⇒ action notification; `[]`/null otherwise |
| `read_at`      | `utc_datetime` | null = unread                                                |
| `meta`         | `jsonb`        | optional — caller-supplied passthrough (e.g. sender id/avatar) |
| `inserted_at`  | `utc_datetime` | timestamps                                                   |
| `updated_at`   | `utc_datetime` |                                                              |

Indexes: `(recipient_id, inserted_at DESC)` for the dropdown list; partial index `(recipient_id) WHERE read_at IS NULL` for the unread count.

`actions` jsonb shape (array of objects):
```json
[{ "key": "approve", "label": "Approve", "redirect_to": "/things/42", "token_max_age": 1800 }]
```

`mix phx_notifications.install` generates the migration (timestamped) into the host app's `priv/repo/migrations/` and runs it. `mix phx_notifications.gen.migration` generates only.

## 2. Core API (`PhxNotifications`)

```elixir
# Send. opts: :title, :url, :actions, :meta, :token_max_age
notify(recipient, body, opts \\ [])           # => {:ok, %Notification{}} | {:error, changeset}

# Run a named action (called by both the LiveComponent and the action endpoint)
execute_action(notification, action_key)       # => {:ok, result} | {:error, reason}

# Read state
mark_read(notification)                         # => {:ok, notification}
mark_all_read(recipient)                        # => {:ok, count}
unread_count(recipient)                         # => integer
list(recipient, opts \\ [])                     # => [%Notification{}], opts: :limit, :before
```

`recipient` is anything implementing the recipient protocol/macro (carries id + PubSub topic).

### Recipient macro

```elixir
defmodule MyApp.User do
  use PhxNotifications.Recipient   # injects has_notifications/0 assoc + topic helper
  schema "users" do
    has_notifications()
    # ...
  end
end
```

`has_notifications/0` defines the `has_many :notifications` association. The macro also derives the per-recipient PubSub topic (`"phx_notifications:#{id}"`).

## 3. Behaviours

### `PhxNotifications.Transport` — *where* a notification goes

```elixir
@callback deliver(notification :: t, recipient :: term, opts :: keyword) ::
            :ok | {:error, reason :: term}
```

- `Transport.PubSub` (v1, always on): broadcasts `{:new_notification, notification}` on the recipient topic. Drives the Bell.
- `Transport.Push` (opt-in, post-v1): FCM/APNS. Designed-for, not built in v1.
- Email / SMS: not built — users implement the behaviour themselves.

Configured transports run for every `notify`. PubSub is implicit and always included.

### `PhxNotifications.Delivery` — *how* delivery runs

```elixir
@callback dispatch(notification :: t, transports :: [module]) :: :ok
```

- `Delivery.Inline` (default): broadcast immediately, run transports in a `Task`.
- `Delivery.Oban` (opt-in, `oban` optional dep): enqueue one delivery job per notification → retries, backoff, at-least-once. Compiles only when Oban is present.

`notify/2,3` is identical regardless of transport or delivery config.

## 4. Bell LiveComponent (`PhxNotifications.Bell`)

Only compiles when `phoenix_live_view` is available (optional dep).

Attrs: `recipient` (required), `limit` (default 20), `class` overrides for the DaisyUI shell wrappers.

Slots:
- `<:trigger :let={count}>` — the icon/button; receives unread count, renders its own badge. Defaults to a DaisyUI bell + badge if omitted. Component never overlays a badge on a custom trigger.
- `<:row :let={n}>` — per-notification rendering. Defaults to a DaisyUI row if omitted.

Behaviour:
- On `mount`/`update`: subscribe to the recipient topic, load unread count + first page.
- On `{:new_notification, n}`: prepend, bump count, no full reload.
- Click handling per inferred type:
  - **info** — no nav; cleared only via "Mark all as read".
  - **link** — navigate to `url`, mark read.
  - **action** — `phx-disable-with` spinner, run `execute_action/2` in a `Task`, mark read on `{:ok, _}`, show inline error on `{:error, _}`.
- `mark_read_on` config (default: link click, action click, mark-all — NOT bell open).

## 5. Action endpoint (out-of-app actions)

A controller + route the host app mounts (documented snippet, or a `PhxNotifications.Router` macro):

```
GET /notifications/:id/actions/:action_key?token=<signed>
```

Flow:
1. Verify `Phoenix.Token` (signed, safe to embed in email/SMS — no session needed).
2. `PhxNotifications.execute_action(notification, action_key)`.
3. Mark read.
4. Redirect by precedence: action's `redirect_to` → notification's `url` → configurable app default (home).

Token expiry, two levels: module default `:action_token_max_age` (config) + per-action `token_max_age` (in the actions jsonb / `notify` opts). Per-action wins.

## 6. `mix.exs`

```elixir
app: :phx_notifications,
version: "0.1.0",
deps: [
  # Required
  {:ecto_sql, "~> 3.12"},
  {:phoenix_pubsub, "~> 2.1"},
  {:jason, "~> 1.4"},
  # Optional
  {:phoenix_live_view, "~> 1.0", optional: true},  # Bell component
  {:oban, "~> 2.18", optional: true},               # Delivery.Oban
  # Dev/test
  {:ecto_sqlite3 or postgrex, only: [:test]},
]
```

Phoenix itself is NOT a hard dep — `phoenix_pubsub` is the only PubSub-related requirement.

## 7. Build order

1. ~~**Scaffold** — `app: :phx_notifications`, modules `PhxNotifications.*`, version `0.1.0`, mix.exs deps.~~ ✅
2. ~~**Schema + changeset**~~ ✅ (`Notification` with inferred type). Migration *generator* (`mix phx_notifications.install`) still TODO; tests use an in-repo migration.
3. ~~**Core context** — `notify`, `list`, `unread_count`, `mark_read`, `mark_all_read`.~~ ✅ Tested against SQLite.
4. ~~**Behaviours + defaults** — `Transport.PubSub`, `Delivery.Inline`. Wire `notify` → delivery → transports.~~ ✅
5. ~~**`execute_action/3` + `ActionHandler` behaviour** — runner dispatching to the configured handler.~~ ✅
6. ~~**Bell LiveComponent** — `<:trigger>`/`<:row>` slots, DaisyUI default markup, click/action UX (async via `send_update`), `PhxNotifications.LiveView` on_mount hook for PubSub forwarding.~~ ✅ Rendering tested via `render_component`.
7. ~~**Action endpoint** — `PhxNotifications.Plug.Actions` + `PhxNotifications.Token` (`plug_crypto`-signed), two-level expiry, redirect precedence. Guarded on Plug being available.~~ ✅ Tested with `Plug.Test`.
8. ~~**Migration generator** — `mix phx_notifications.install` / `.gen.migration` (`--binary-id` flag). Shared `PhxNotifications.Migration.change/1` body (dogfooded by the test migration).~~ ✅
9. **Guides + two examples** — default DaisyUI; custom trigger icon + custom avatar row. *(next)*
10. **Optional adapters** (post-v1) — `Delivery.Oban`, `Transport.Push`.

> Progress note: steps 1–8 implemented and tested (27 passing tests, warning-clean compile)
> on branch `feat/core-library`. Local folder remains `phoenix_notifications/` (cosmetic);
> package/app/modules are `phx_notifications` / `PhxNotifications.*` as decided.

## Resolved implementation decisions

- **PK type** — default `bigserial` (auto-incrementing integer); generator flag `--binary-id` for apps standardized on UUIDs. Rationale: match the host app's user-table PK so `recipient_id` lines up without casting. Enumerability of integer IDs is a non-issue here because the action endpoint is token-signed.
- **Recipient coupling** — macro (`use PhxNotifications.Recipient` + `has_notifications/0`). Simpler than a protocol; revisit only if non-Ecto recipients are ever needed.
- **Router integration** — copy-pasteable `forward`, mirroring `phx_media_library`'s plug pattern. No router macro:
  ```elixir
  # router.ex
  forward "/notifications", PhxNotifications.Plug.Actions
  ```
  One line, non-invasive, idiomatic.
- **`on_action` registration** — a single configured handler module implementing the `PhxNotifications.ActionHandler` behaviour:
  ```elixir
  config :phx_notifications, action_handler: MyApp.NotificationActions

  defmodule MyApp.NotificationActions do
    @behaviour PhxNotifications.ActionHandler
    @impl true
    def handle_action(action_key, notification, ctx), do: {:ok, ...} | {:error, reason}
  end
  ```
  **Why not the alternatives:** a per-component `on_action` closure can't serve the email/SMS action endpoint (no LiveView/socket exists there); storing an MFA in the action jsonb puts code references in the DB (refactor-fragile + security footgun). A configured behaviour module is the only option that works identically across both the LiveComponent and the token endpoint, stays compile-checked/testable, and keeps no code in the database. Action-specific data travels in `notification.meta` (JSON-safe).

## Open implementation items (decide during build, non-blocking)

_None — all major design decisions resolved. Remaining choices are mechanical and surface during coding._
