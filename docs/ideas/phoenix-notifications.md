# phx_notifications

## Problem Statement

How might we give Phoenix developers a drop-in, self-contained in-app notification system so they stop hand-rolling the same bell icon, PubSub wiring, and read-state logic in every project?

## Recommended Direction

A single `notifications` table with three implied types (info, link, action) driven by which fields are populated. A self-contained LiveComponent handles the bell icon, unread count, dropdown panel, PubSub subscription, and async action execution — the developer drops it into their layout and provides an `on_action` callback for business logic.

The notification type is inferred from the data: a notification with a `url` navigates on click and marks itself read; one with `actions` (jsonb) shows buttons, runs the callback in a Task, shows a spinner, and marks read on completion; one with neither is informational and only cleared via "Mark all as read". This covers ~95% of real notification patterns without requiring an explicit type field.

The philosophy mirrors `phoenix_media_library`: add one macro to your User schema, run one mix task for the migration, call one function to send, drop one component in your layout. The internals are invisible unless you need to reach past them.

## Packaging (mirrors phx_media_library)

Elixir-first, Phoenix-optional — the same dependency shape proven in `phx_media_library`:

- **Required core:** `ecto_sql` + `phoenix_pubsub` (PubSub is the v1 transport and a tiny standalone lib, not full Phoenix). A pure-Elixir/Ecto app can `notify/2` and read notifications from the DB with no UI.
- **Optional:** `phoenix_live_view` (`optional: true`) — the Bell component only compiles when the host app already has LiveView. Push/Oban transports are optional too.

This keeps us Phoenix-first in practice (where most users live) without coupling the core to Phoenix.

**Initial version: `0.1.0`.** Stay in the `0.x` range while the API settles — same convention as `phx_media_library`, which is still `0.x` despite being fairly mature. No rush to `1.0`.

### CLI (follows media_library's own-namespace convention)

Tasks namespace under the app name, **not** under `phx.gen.*` (which is reserved for Phoenix core):

- `mix phx_notifications.install` — generates and runs the migration
- `mix phx_notifications.gen.migration` — generates a migration only
- Maintenance (post-v1, optional): `phx_notifications.purge_read`, `phx_notifications.doctor`, `phx_notifications.stats`

### Bell component: one component, two slots, two examples

One component, customized via slots rather than forked into style variants:

- **`<:trigger>` slot** — the bell icon / button. Defaults to a DaisyUI bell with unread badge; users swap in their own icon, button, or avatar-with-count to match their stack. The unread count is passed via `:let` so a custom trigger renders its own badge however it wants. The component never overlays its own badge on a user-provided trigger — it does not assume or override the trigger's layout.
- **`<:row :let={n}>` slot** — per-notification rendering. Defaults to a DaisyUI row; users render whatever they want.

Default styling is DaisyUI (ships with Phoenix 1.8) so it's demoable in a fresh app with zero config. The slots are the standalone/raw-Tailwind escape hatch — no second component to maintain.

Two examples ship in the guides:
1. **Default** — DaisyUI bell + DaisyUI rows, drop-in, no slots provided.
2. **Custom** — a user-notification scenario: custom trigger icon and a custom row rendering the sender's avatar, name, and message.

## Transports (loadable later)

Just as media storage grows from local filesystem → S3, notification *delivery* grows from in-app → out-of-app via a `PhxNotifications.Transport` behaviour defined from day one. The caller's `notify/2,3` API never changes; only the transports behind it do.

```elixir
config :phx_notifications,
  transports: [
    PhxNotifications.Transport.PubSub,   # v1, always on — in-app LiveComponent
    PhxNotifications.Transport.Push,      # natural upgrade — FCM/APNS
  ],
  # optional: route delivery through Oban instead of inline Tasks
  delivery: PhxNotifications.Delivery.Oban  # default: PhxNotifications.Delivery.Inline
```

- **PubSub (v1)** — writes to DB, broadcasts, drives the LiveComponent. Zero deps beyond Phoenix.
- **Push / FCM / APNS** — the blessed upgrade path, designed for concretely. Opt-in adapter.
- **Email** — *not built by us.* The behaviour leaves the seam open; anyone who wants email implements the behaviour. No Swoosh dependency shipped by default. Configurable and fully skippable.
- **SMS / Twilio** — future consideration only. Noted here so the behaviour stays general enough to accommodate it; not a v1 concern.

### Oban as an optional delivery strategy

Oban is a different axis from the transports above — it's not *where* a notification goes but *how* delivery runs. By default delivery is inline (`PhxNotifications.Delivery.Inline`: broadcast immediately, run transports in a `Task`). Users who already have Oban can opt into `PhxNotifications.Delivery.Oban`, which enqueues a delivery job per notification instead — giving retries, backoff, and at-least-once guarantees, especially valuable once out-of-app transports (Push) are in play.

- `oban` is `optional: true` — never a required dependency, same as in media_library.
- The seam is a `PhxNotifications.Delivery` behaviour defined from day one; the Oban adapter only compiles when Oban is present.
- The caller's `notify/2,3` API is unchanged regardless of delivery strategy.

### Transport-agnostic action execution

Because an action can be triggered from outside a LiveView (e.g. an email or SMS link), action execution **cannot live inside the LiveComponent**. It is a shared core function — `PhxNotifications.execute_action/2` — that both the component (in a Task) and a plain controller endpoint call. This mirrors how media_library separates the storage behaviour from the upload flow.

Out-of-app action flow (tokenized endpoint, no session required):

```
GET /notifications/:id/actions/:action_key?token=<signed>
  → verify Phoenix.Token (safe to embed in a link)
  → PhxNotifications.execute_action(notification, action_key)
  → mark read
  → redirect
```

**Token expiry — two levels.** A module-level default (`config :phx_notifications, action_token_max_age: <seconds>`) plus a per-notification override on `notify/3` (`token_max_age:`). Different notifications need wildly different lifetimes: a shared-file action may stay valid 30 days, a password-reset-style action only 30 minutes. The per-notification value wins; the module default applies otherwise.

**Redirect target precedence:**
1. the action's own `redirect_to`, if set
2. else the notification's `url` (link-type notifications)
3. else a configurable app default (home)

## Key Assumptions to Validate

- [ ] Most Phoenix developers are building monoliths — validate by checking Phoenix community surveys and forum threads before designing around any distributed pattern
- [ ] Three notification types (info/link/action) cover the real use cases — validate by surveying 5-10 Phoenix apps in the wild and cataloguing their notification patterns
- [ ] A self-contained LiveComponent is acceptable DX — validate that not owning the LiveView doesn't prevent customisation needs (CSS, layout, pagination)
- [ ] `phx-disable-with` + Task async is sufficient for action button UX — validate that no edge cases require more explicit loading state management

## MVP Scope

**In:**
- `mix phx_notifications.install` — generates and runs the migration
- `use PhxNotifications.Recipient` + `has_notifications()` macro for the User schema
- `PhxNotifications.notify/2,3` — send info, link, or action notifications
- `PhxNotifications.Bell` LiveComponent — bell icon, unread count badge, dropdown list, mark-as-read
- PubSub subscription wired automatically on Bell mount
- Async action handling with spinner and inline error state
- Configurable `mark_read_on` behaviour (default: link click, action click, mark-all button — NOT bell open)

**Out of v1:**
- Email or push delivery
- Mass/broadcast notifications
- Notification grouping ("John and 3 others...")
- Per-user notification preferences
- Pagination beyond a reasonable default limit

## Not Doing (and Why)

- **Fan-out / audience table pattern** — clean for microservices (Kafka fan-in, no user state sync), but adds read complexity for monolith users who get no benefit; document as an extension pattern for advanced users
- **Email delivery** — not built by us at all; exposed as a transport seam users can implement themselves. Keeps the Swoosh dependency surface out of the library entirely.
- **Notification grouping** — product-level logic that belongs in the caller, not the library; too many ways to group for the library to guess correctly
- **Required Oban dependency** — never required; inline `Task` delivery is the default and sufficient for in-app delivery. Oban is available as an *optional* delivery strategy (`PhxNotifications.Delivery.Oban`) for users who already have it — see Transports section.

## Resolved

- **Bell customization** — slots, not a render callback. Two slots: `<:trigger>` (bell icon/button) and `<:row :let={n}>` (per-notification rendering). See Packaging section.
- **CSS strategy** — one component, DaisyUI-styled by default (demoable in fresh Phoenix 1.8 app), slots as the raw-Tailwind/standalone escape hatch. No separate UI package, no parallel style variants.
- **Generator name** — `mix phx_notifications.install` (own-namespace convention from media_library), not `phx.gen.notifications`.
- **Package / module name** — `phx_notifications`, module prefix `PhxNotifications`, for consistency with the sibling `phx_media_library`. Avoids `phx.notifications` which would squat Phoenix's reserved `phx.` namespace.
- **`on_action` return shape** — stays a simple `{:ok, _} | {:error, reason}`; redirect-after-action is handled by transport-agnostic precedence (see Transports section).
- **Action-token expiry** — two levels: module-level `action_token_max_age` default + per-notification `token_max_age:` override. Per-notification wins. (See Transports section.)
- **Trigger badge ownership** — `<:trigger>` receives the unread count via `:let`; the trigger renders its own badge. The component never overlays a badge on a custom trigger.

## Open Questions

_None blocking — ready for an implementation plan._
