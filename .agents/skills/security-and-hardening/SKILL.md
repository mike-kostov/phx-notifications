---
name: security-and-hardening
description: Hardens code against vulnerabilities. Use when handling user input, authentication, data storage, payment processing, or external OCPP/OCPI integrations. Use when building any feature that accepts untrusted data, manages user sessions, or handles money.
---

# Security and Hardening

## Overview

Security-first development practices for the CSMS platform. Treat every external input as hostile, every secret as sacred, and every authorization check as mandatory. Security isn't a phase — it's a constraint on every line of code that touches user data, authentication, OCPP messages, or payment processing.

## When to Use

- Building anything that accepts user input (LiveView events, HTTP, WebSocket)
- Implementing authentication or authorization (phx_gen_auth, OCPI tokens, RFID)
- Storing or transmitting sensitive data (payment info, session data, credentials)
- Integrating with external APIs (Stripe webhooks, OCPI partners, OCPP chargers)
- Adding file uploads, webhooks, or callbacks
- Implementing OCPP Basic Auth for charger connections

## The Three-Tier Boundary System

### Always Do (No Exceptions)

- **Validate all external input** at system boundaries (WebSocket handlers, HTTP controllers, LiveView events)
- **Parameterize all database queries** — never use string interpolation in Ecto raw queries
- **Encode output** — Phoenix/HEEx auto-escapes by default; never bypass with `raw/1` on user-controlled data
- **Use HTTPS** for all external communication (Stripe, OCPI partners)
- **Hash passwords** with Bcrypt (phx_gen_auth uses this by default — don't change it)
- **Never use `String.to_atom/1` on user input** — atoms are not garbage collected; this is a memory exhaustion vector
- **Verify Stripe webhook signatures** before processing any webhook payload
- **Run `mix deps.audit`** before any release

### Ask First (Requires Human Approval)

- Adding new authentication flows or changing auth logic
- Storing new categories of sensitive data (full card numbers, PII beyond email)
- Adding new external service integrations (OCPI partners, map providers)
- Changing OCPP Basic Auth credential validation logic
- Adding new admin capabilities or elevated roles
- Granting OCPI access to a new partner

### Never Do

- **Never commit secrets** to version control (API keys, OCPP passwords, Stripe keys)
- **Never log sensitive data** (passwords, Stripe payment method IDs, OCPI tokens)
- **Never trust client-side validation** as a security boundary — always validate on the server
- **Never use `String.to_atom/1` on user input** (memory leak risk)
- **Never return stack traces** or internal error details to API consumers
- **Never store sessions or auth tokens in localStorage** — use signed, httpOnly cookies (Phoenix sessions handle this by default)
- **Never process a Stripe webhook without verifying the signature**

## OCPP-Specific Security

### Basic Auth for Charger Connections

OCPP 1.6 over WebSocket typically uses HTTP Basic Auth. Validate credentials before upgrading the connection:

```elixir
defmodule ChargerStationsMsWeb.OCPPSocket do
  def connect(%{"Authorization" => auth_header}, socket, _connect_info) do
    with {:ok, {charger_id, password}} <- decode_basic_auth(auth_header),
         {:ok, charger} <- Chargers.authenticate(charger_id, password) do
      {:ok, assign(socket, :charger_id, charger.ocpp_id)}
    else
      {:error, _} ->
        # Don't reveal whether it's the ID or password that's wrong
        {:error, :unauthorized}
    end
  end

  defp decode_basic_auth("Basic " <> encoded) do
    with {:ok, decoded} <- Base.decode64(encoded),
         [id, pass] <- String.split(decoded, ":", parts: 2) do
      {:ok, {id, pass}}
    else
      _ -> {:error, :invalid_header}
    end
  end
end
```

### Never Trust the Charger

Charger firmware can be buggy, outdated, or compromised. Treat all OCPP message payloads as untrusted input:

```elixir
# Always validate OCPP payloads at the handler boundary
def handle_boot_notification(charger_id, payload) when is_map(payload) do
  # Don't assume fields exist or have the expected type
  model  = Map.get(payload, "chargePointModel", "Unknown")
  vendor = Map.get(payload, "chargePointVendor", "Unknown")

  # Clamp string lengths before persisting
  attrs = %{
    ocpp_id: charger_id,
    model:   String.slice(model, 0, 50),
    vendor:  String.slice(vendor, 0, 50)
  }

  # ... persist and respond
end

def handle_boot_notification(_charger_id, _invalid_payload), do: {:error, :invalid_payload}
```

## OCPI Security

### Token Validation

Every OCPI request from a partner must carry a valid `Authorization` token:

```elixir
defmodule ChargerStationsMsWeb.OCPIAuthPlug do
  import Plug.Conn

  def call(conn, _opts) do
    with ["Token " <> token] <- get_req_header(conn, "authorization"),
         {:ok, _partner} <- OCPI.Partners.authenticate_token(token) do
      conn
    else
      _ ->
        conn
        |> send_resp(401, Jason.encode!(%{status_code: 2001, status_message: "Unauthorized"}))
        |> halt()
    end
  end
end
```

### Validate OCPI Payloads

OCPI partner data (CDRs, Tokens, Commands) is untrusted external data. Validate it with Ecto changesets or explicit type checks before using it:

```elixir
# Validate incoming OCPI Token from a partner before storing
def validate_token(params) do
  %Token{}
  |> Token.changeset(params)
  |> case do
    %{valid?: true} = changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)}
    changeset -> {:error, changeset}
  end
end
```

## Payment Security (Stripe)

### Webhook Signature Verification

Always verify Stripe webhooks before processing them:

```elixir
defmodule ChargerStationsMsWeb.StripeWebhookController do
  use ChargerStationsMsWeb, :controller

  @stripe_webhook_secret System.get_env("STRIPE_WEBHOOK_SECRET")

  def handle(conn, _params) do
    with [sig_header] <- get_req_header(conn, "stripe-signature"),
         {:ok, event} <- Stripe.Webhook.construct_event(
           conn.assigns.raw_body,
           sig_header,
           @stripe_webhook_secret
         ) do
      process_event(conn, event)
    else
      _ ->
        conn
        |> put_status(400)
        |> json(%{error: "Invalid signature"})
    end
  end
end
```

### Never Log Payment Data

```elixir
# BAD: Logs payment method ID
Logger.info("Processing payment for customer #{customer_id} with #{payment_method_id}")

# GOOD: Log only what's safe
Logger.info("Processing payment for customer #{customer_id}")
```

## Secrets Management

```
Environment variables (never in code):
  STRIPE_SECRET_KEY       → Stripe API key
  STRIPE_WEBHOOK_SECRET   → Stripe webhook signing secret
  SECRET_KEY_BASE         → Phoenix session encryption key
  DATABASE_URL            → Database connection string
  OCPI_SHARED_SECRET      → Initial OCPI handshake token

.gitignore must include:
  .env
  .env.local
  config/prod.secret.exs  (if used)
```

**Always use runtime configuration for secrets:**

```elixir
# config/runtime.exs — read at runtime, not compile time
config :charger_stations_ms, :stripe,
  secret_key: System.fetch_env!("STRIPE_SECRET_KEY"),
  webhook_secret: System.fetch_env!("STRIPE_WEBHOOK_SECRET")
```

## Security Review Checklist

```markdown
### Authentication
- [ ] Charger OCPP connections authenticate via Basic Auth before WebSocket upgrade
- [ ] OCPI partner tokens validated before any module handler
- [ ] Stripe webhook signatures verified before processing
- [ ] User sessions use signed, httpOnly cookies (Phoenix default)

### Authorization
- [ ] Every LiveView route in an authenticated `live_session`
- [ ] Users can only access their own charging sessions and receipts
- [ ] Admin operations require explicit role check

### Input
- [ ] All OCPP message payloads validated at the handler boundary
- [ ] All OCPI partner payloads validated via changesets
- [ ] No `String.to_atom/1` on user-controlled data
- [ ] String lengths clamped before persisting

### Data
- [ ] No secrets in code or version control
- [ ] No sensitive data in logs
- [ ] Payment data not stored locally (delegated to Stripe)

### Infrastructure
- [ ] `mix deps.audit` clean
- [ ] Error responses don't expose internal details or stack traces
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "Chargers are our hardware, they're trusted" | Firmware can be buggy or compromised. Treat all OCPP input as untrusted. |
| "This is an internal OCPI endpoint, security doesn't matter" | All external integrations are attack surfaces. Validate tokens everywhere. |
| "We'll add Stripe signature verification later" | A missing signature check is a complete bypass. Add it from day one. |
| "The atom table is huge, `String.to_atom` is fine" | It's bounded. An attacker who controls charger IDs can exhaust it. Use `String.to_existing_atom/1` or avoid atoms entirely. |

## Red Flags

- OCPP WebSocket connections accepted without authentication
- OCPI endpoints without token validation
- Stripe webhooks processed without signature verification
- `String.to_atom/1` called with user-controlled input
- Secrets in `config/*.exs` files committed to the repo
- Raw user input rendered without escaping
- Stack traces returned in API error responses

## Verification

After implementing security-relevant code:

- [ ] `mix deps.audit` shows no critical vulnerabilities
- [ ] No secrets in source code or git history
- [ ] All external input validated at system boundaries
- [ ] Charger auth happens before WebSocket upgrade completes
- [ ] OCPI partner tokens validated before module handler runs
- [ ] Stripe webhook signatures verified
- [ ] Error responses don't expose internal details
