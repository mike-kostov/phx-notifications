---
name: documentation-and-adrs
description: Records decisions and documentation. Use when making architectural decisions, choosing between competing OCPP/OCPI approaches, or when you need to record context that future engineers and agents will need to understand the codebase.
---

# Documentation and ADRs

## Overview

Document decisions, not just code. The most valuable documentation captures the *why* — the context, constraints, and trade-offs that led to a decision. Code shows *what* was built; documentation explains *why it was built this way* and *what alternatives were considered*. This context is essential for future engineers and agents working in the codebase.

For a system like CSMS, architectural decisions are often irreversible: the OCPP version, the DB schema hierarchy, the supervision tree structure, the payment provider. Write ADRs for these. Future-you (and the next AI agent) will thank you.

## When to Use

- Choosing between OCPP 1.6 and 2.0.1
- Deciding on the DB schema structure (OCPI hierarchy vs flat)
- Choosing an OCPI module implementation order
- Selecting how to handle OCPP authentication
- Any decision that would be expensive to reverse
- When you find yourself explaining the same architectural choice repeatedly

**When NOT to use:** Don't document obvious code. Don't add comments that restate what the code already says. Don't write ADRs for trivial implementation choices.

## Architecture Decision Records (ADRs)

ADRs capture the reasoning behind significant technical decisions. They're the highest-value documentation you can write.

### When to Write an ADR

- Choosing which OCPP version to support (1.6 vs 2.0.1)
- Deciding on the DB schema hierarchy (locations → evses → connectors)
- Choosing a supervision strategy for charger processes
- Selecting a payment provider (Stripe, Adyen, etc.)
- Deciding how to handle OCPI partner authentication
- Any decision that would take more than one meeting to re-derive

### ADR Template

Store ADRs in `docs/decisions/` with sequential numbering:

```markdown
# ADR-001: Use OCPI-First DB Schema from Day One

## Status
Accepted

## Date
2025-01-15

## Context
We are building an OCPP backend. OCPP's data model uses:
  ChargePoint → Connector

But OCPI's data model (needed for partner integrations) uses:
  Location → EVSE → Connector

We need to choose a DB schema at project start that won't require
a painful migration later. OCPI interoperability is planned for Phase 2.

## Decision
Design the schema using the OCPI hierarchy from day one:
  locations → evses → connectors

Map OCPP concepts to OCPI concepts:
  ChargePoint = Location + EVSE
  Connector = Connector

## Alternatives Considered

### OCPP-First Schema (charge_points → connectors)
- Pros: Simpler to start with, maps directly to OCPP messages
- Cons: Requires a full schema migration when OCPI is added, likely breaking
- Rejected: The migration cost is too high for a foreseeable requirement

### Separate schemas (ocpp_charge_points + ocpi_locations)
- Pros: Each domain has its natural model
- Cons: Dual write problem, data consistency issues
- Rejected: Operational complexity not justified at this scale

## Consequences
- OCPP ChargePoint IDs need to be mapped to EVSE IDs in the handler layer
- StatusNotification must update the evse/connector status (not a charge_point row)
- OCPI Locations module implementation is significantly simpler
- BootNotification handler creates/updates an EVSE, not a charge_point
```

### ADR Lifecycle

```
PROPOSED → ACCEPTED → (SUPERSEDED or DEPRECATED)
```

- **Don't delete old ADRs.** They capture historical context.
- When a decision changes, write a new ADR that references and supersedes the old one.

## Inline Documentation

### When to Comment

Comment the *why*, not the *what*:

```elixir
# BAD: Restates the code
# Increment heartbeat counter by 1
state = %{state | heartbeat_count: state.heartbeat_count + 1}

# GOOD: Explains non-obvious intent
# OCPP 1.6 spec §4.3: The CSMS must respond to Heartbeat within the configured interval.
# If we don't respond, some charger firmware will interpret silence as a disconnect
# and will reset the connection — causing unnecessary reconnect storms.
def handle_cast(:heartbeat, state) do
  send_response(state.pid, build_heartbeat_response())
  {:noreply, state}
end
```

### Document Known Gotchas

```elixir
@doc """
Handles a MeterValues OCPP message.

## Important
The `sampledValue` field is technically required by the spec but many charger
manufacturers omit it or send `nil`. Always handle the nil case — crashing here
means the charger loses its connection and the transaction must be recovered manually.

See ADR-004 for the decision to handle malformed MeterValues gracefully vs. strict validation.
"""
def handle_meter_values(charger_id, payload) do
  # ...
end
```

### When NOT to Comment

```elixir
# Don't comment self-explanatory code
def full_name(charger), do: "#{charger.vendor} #{charger.model}"

# Don't leave TODO comments for things you should just do now
# TODO: add error handling  ← Just add it

# Don't leave commented-out code
# def old_handler(msg), do: ...  ← Delete it, git has history
```

## The README

Keep `README.md` current as the project grows:

```markdown
# Charger Stations Management System (CSMS)

EV charging infrastructure backend built on Elixir/Phoenix/OTP.

## Quick Start
1. `docker-compose up -d`  (starts PostgreSQL)
2. `mix setup`             (deps + db create/migrate + seeds)
3. `mix phx.server`        (starts the server)

## Commands
| Command | Description |
|---------|-------------|
| `mix phx.server` | Start development server |
| `mix test` | Run test suite |
| `mix precommit` | Lint + format + test (run before committing) |
| `mix ecto.migrate` | Run pending migrations |

## Architecture
Three domains:
- **OCPP** (`lib/charger_stations_ms/ocpp/`) — WebSocket connections, GenServer per charger
- **OCPI** (`lib/charger_stations_ms/ocpi/`) — REST partner integrations (future)
- **Portal** (`lib/charger_stations_ms/portal/`) — Customer-facing UI and payments

See `docs/decisions/` for Architecture Decision Records.
```

## CSMS-Specific Documentation Priorities

In rough priority order, these decisions warrant ADRs:

1. **OCPP version choice** (1.6 vs 2.0.1) — different wire format, security model, and feature set
2. **DB schema hierarchy** (OCPI-first vs OCPP-first) — very expensive to change
3. **Supervision strategy** (one GenServer per charger vs pooled) — affects crash isolation
4. **ChargerRegistry implementation** (pg_core Presence vs local Registry) — affects multi-node
5. **OCPI authentication model** — TOKEN_A/B/C handshake complexity
6. **Payment provider** — contractual and technical lock-in
7. **CDR storage strategy** — how Charge Detail Records are persisted and exported

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "The code is self-documenting" | Code shows what. It doesn't show why, what alternatives were rejected, or what constraints apply. |
| "We'll write ADRs when the API stabilizes" | ADRs should be written *as* you make decisions, not after. The decision context fades fast. |
| "ADRs are overhead" | A 10-minute ADR prevents a 2-hour debate about the same decision six months later. |
| "Nobody reads docs" | Agents do. Future engineers do. Your 3-months-later self does. |

## Red Flags

- Making an irreversible architectural decision (schema, supervision, OCPP version) without any written rationale
- TODO comments that have been there for days
- Commented-out code instead of deletion
- No README quick-start that actually works

## Verification

After documenting:

- [ ] ADRs exist for all significant architectural decisions
- [ ] README covers quick start, commands, and architecture overview
- [ ] Known gotchas documented inline where they matter
- [ ] No commented-out code remains
- [ ] `docs/decisions/` directory exists and is committed
