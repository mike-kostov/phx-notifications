# Multi-channel delivery & fallback (future idea)

> **Status:** idea, not scheduled. The 0.1 line ships *simple building bricks* only. This is a
> north-star for later — the kind of feature that makes a developer skim the README and go
> "nice," then adopt the library.

## Guiding philosophy

Ship composable primitives; let library users assemble complex delivery policies themselves.
We only promote a policy to a first-class feature once it's clearly common, clearly boring to
use, and we understand its edges. Until then: small, honest bricks.

So the near-term scope stays:

- `Transport` (where a notification goes) — leaf adapters: `PubSub`, later `Push`, `Email`, `SMS`.
- `Delivery` (how dispatch runs) — `Inline`, later `Oban`.
- `ActionHandler` (what a button does).

Everything below is **explicitly deferred**.

## Two different things people call "fallback"

1. **Acceptance fallback** — "try Push; if the user has no device token / the provider rejects,
   try Email instead." Synchronous-ish and genuinely simple to build.
2. **Engagement escalation** — "send Push; if it isn't *read* within N minutes, send Email."
   A different beast: needs scheduled re-checks and read-state polling, so it only works on top
   of `Delivery.Oban`. (PagerDuty-style.)

## The crux: a transport result contract

Most channels don't tell you synchronously whether a human *received* (let alone saw) a message —
you hand a payload to FCM/Twilio and get back "accepted," not "delivered to a person." And errors
are ambiguous. So before any fallback can be correct, each `Transport.deliver/2` must distinguish:

- `:ok` — accepted by the channel/provider.
- `{:error, :unavailable}` — the user cannot be reached this way (no token, no phone). → **fall back**.
- `{:error, :transient}` — temporary send failure (provider 5xx, timeout). → **retry, don't fall back** (Oban's job).

Getting this contract right is the actual design work. The chaining is easy once it exists.

## Architecture (no third axis needed)

**Acceptance fallback = a composite `Transport`.** `Transport.Fallback` *is itself* a `Transport`
that wraps an ordered list and tries each until one accepts:

    config :phx_notifications,
      transports: [
        {PhxNotifications.Transport.Fallback, [Transport.Push, Transport.SMS, Transport.Email]}
      ]

It implements the same behaviour, so nothing above it changes; `{:error, :unavailable}` means "try
the next one." This keeps fallback on the existing Transport axis — composable, boring, no new
concept.

**Engagement escalation = a `Delivery.Oban` policy.** Time/read-based escalation needs scheduling:
send channel 1, enqueue a "still unread? escalate to channel 2" job for later. This is the only
flavor that needs more than a composite transport, and it naturally belongs to the durable
delivery strategy.

## Prerequisite: recipient contact resolution

Fallback needs to know a user's available contact methods. That's recipient data the transports
must resolve — likely new **optional** callbacks on `PhxNotifications.Recipient`
(e.g. `push_tokens/1`, `phone/1`, `email/1`), or values carried in `notification.meta`. This must
be decided *before* building `Transport.Push`, since all leaf transports will read from it.

## Suggested sequencing (boring-first)

1. ~~Leaf transports — `Transport.Push`, `Transport.Email`, `Transport.SMS` — that just deliver, and
   nail the `:ok / :unavailable / :transient` result contract.~~ ✅ Shipped as provider-agnostic
   adapters delegating to `Transport.Sender` (configured sender per channel). The sender resolves
   the destination itself, so recipient contact-resolution callbacks are **not** needed yet.
2. ~~`Delivery.Oban` — retries on `:transient`.~~ ✅ Immediate in-app PubSub + one durable job per
   out-of-app transport; `:unavailable` cancels, `:transient` retries.
3. `Transport.Fallback` (composite) — acceptance fallback ("Push → degrade to Email").
4. *Only if needed:* engagement escalation (timed, read-based) as an Oban-driven policy.

## What we deliberately leave to users (for now)

- Channel-selection policy per notification (urgent vs FYI) — users can pass their own transport
  list / build their own composite today.
- Quiet hours, rate limiting, per-user channel preferences — product concerns that belong in the
  caller, not the library.
- Delivery receipts / webhook ingestion from providers — out of scope; users wire their own.

These stay user-land until there's a clearly common, clearly boring shape worth absorbing.
