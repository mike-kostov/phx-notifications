# phoenix_notifications

## Problem Statement

How might we give Phoenix developers a drop-in, self-contained in-app notification system so they stop hand-rolling the same bell icon, PubSub wiring, and read-state logic in every project?

## Recommended Direction

A single `notifications` table with three implied types (info, link, action) driven by which fields are populated. A self-contained LiveComponent handles the bell icon, unread count, dropdown panel, PubSub subscription, and async action execution — the developer drops it into their layout and provides an `on_action` callback for business logic.

The notification type is inferred from the data: a notification with a `url` navigates on click and marks itself read; one with `actions` (jsonb) shows buttons, runs the callback in a Task, shows a spinner, and marks read on completion; one with neither is informational and only cleared via "Mark all as read". This covers ~95% of real notification patterns without requiring an explicit type field.

The philosophy mirrors `phoenix_media_library`: add one macro to your User schema, run one mix task for the migration, call one function to send, drop one component in your layout. The internals are invisible unless you need to reach past them.

## Key Assumptions to Validate

- [ ] Most Phoenix developers are building monoliths — validate by checking Phoenix community surveys and forum threads before designing around any distributed pattern
- [ ] Three notification types (info/link/action) cover the real use cases — validate by surveying 5-10 Phoenix apps in the wild and cataloguing their notification patterns
- [ ] A self-contained LiveComponent is acceptable DX — validate that not owning the LiveView doesn't prevent customisation needs (CSS, layout, pagination)
- [ ] `phx-disable-with` + Task async is sufficient for action button UX — validate that no edge cases require more explicit loading state management

## MVP Scope

**In:**
- `mix notifications.install` — generates and runs the migration
- `use PhoenixNotifications.Recipient` + `has_notifications()` macro for the User schema
- `PhoenixNotifications.notify/2,3` — send info, link, or action notifications
- `PhoenixNotifications.Bell` LiveComponent — bell icon, unread count badge, dropdown list, mark-as-read
- PubSub subscription wired automatically on Bell mount
- Async action handling with spinner and inline error state
- Configurable `mark_read_on` behaviour (default: link click, action click, mark-all button — NOT bell open)

**Out of v1:**
- Email or push delivery
- Mass/broadcast notifications
- Notification grouping ("John and 3 others...")
- Per-user notification preferences
- Pagination beyond a reasonable default limit
- Oban-backed delivery guarantees

## Not Doing (and Why)

- **Fan-out / audience table pattern** — clean for microservices (Kafka fan-in, no user state sync), but adds read complexity for monolith users who get no benefit; document as an extension pattern for advanced users
- **Email delivery** — separate dependency surface (Swoosh), separate concern, separate v2
- **Notification grouping** — product-level logic that belongs in the caller, not the library; too many ways to group for the library to guess correctly
- **Oban dependency** — makes the library heavier for users who don't have Oban; async Task is sufficient for in-app delivery; revisit if email delivery is added

## Open Questions

- Should the Bell accept a slot/inner block for custom notification row rendering, or expose a render callback?
- CSS strategy: unstyled + class props, Tailwind-first with overrides, or ship a separate `phoenix_notifications_ui` package?
- Should `on_action` return `{:ok, _} | {:error, reason}` or something richer (e.g. redirect after action)?
- Is `mix notifications.install` the right generator name, or follow Phoenix conventions like `mix phx.gen.notifications`?
