---
name: api-and-interface-design
description: Guides stable API and interface design. Use when designing OCPP message contracts, OCPI module boundaries, LiveView-to-context interfaces, or any public surface between modules. Use before implementing any protocol message handler or external integration.
---

# API and Interface Design

## Overview

Design stable, well-documented interfaces that are hard to misuse. Good interfaces make the right thing easy and the wrong thing hard. This applies to OCPP message contracts, OCPI REST endpoints, Elixir context module boundaries, and any surface where one piece of code talks to another.

## When to Use

- Designing new OCPP message handlers
- Defining OCPI module endpoints (Locations, Sessions, CDRs, etc.)
- Creating boundaries between Elixir context modules
- Establishing the DB schema that informs the API shape
- Changing existing public interfaces

## Core Principles

### Hyrum's Law

> With a sufficient number of users of an API, all observable behaviors of your system will be depended on by somebody, regardless of what you promise in the contract.

For OCPP/OCPI this means: every field you return, every error code you emit, every timing behavior — all become implicit contracts with charger firmware and partner systems. Design implications:

- **Be intentional about what you expose.** Every observable behavior is a potential commitment.
- **Don't leak implementation details.** If partners can observe it, they will depend on it.
- **Plan for deprecation at design time.** OCPP 2.0.1 is a breaking change from 1.6 — plan the migration path.

### Contract First

Define the interface before implementing it. For OCPP, write the expected message structure and response first:

```elixir
# Define the contract first as typespecs and @doc
@doc """
Handles an OCPP BootNotification request.

## Message payload shape
  %{
    "chargePointModel"  => String.t(),
    "chargePointVendor" => String.t(),
    "chargePointSerialNumber" => String.t() | nil,
    "firmwareVersion" => String.t() | nil
  }

## Returns
  {:ok, %{status: "Accepted" | "Pending" | "Rejected",
          current_time: DateTime.t(),
          interval: pos_integer()}}
  {:error, reason}
"""
@spec handle_boot_notification(charger_id :: String.t(), payload :: map()) ::
        {:ok, boot_response()} | {:error, term()}
def handle_boot_notification(charger_id, payload) do
  # implementation follows the spec
end
```

### Consistent Error Semantics

Pick one error strategy and use it everywhere:

```elixir
# Context functions always return {:ok, result} | {:error, reason}
# Reason is either a changeset, an atom, or a structured map — never a bare string

# Good: Consistent return shapes
{:ok, session}
{:error, :charger_offline}
{:error, :unauthorized_id_tag}
{:error, %Ecto.Changeset{}}

# Bad: Mixed patterns
{:ok, session}
nil          # when not found
"error text" # when something went wrong
```

### Validate at Boundaries

Trust internal Elixir code. Validate at system edges where external input enters:

```elixir
# Validate OCPP messages at the WebSocket handler boundary
def handle_frame({:text, raw_msg}, state) do
  with {:ok, decoded} <- Jason.decode(raw_msg),
       {:ok, message}  <- OCPP.Message.parse(decoded) do
    dispatch_message(message, state)
  else
    {:error, reason} ->
      Logger.warning("Invalid OCPP message from #{state.charger_id}: #{inspect(reason)}")
      {:ok, state}  # don't crash the handler on bad input
  end
end
```

Where validation belongs:
- WebSocket frame handlers (OCPP messages from chargers)
- HTTP controllers/plugs (OCPI requests from partners)
- LiveView event handlers (user input)
- Webhook handlers (Stripe callbacks)

Where validation does NOT belong:
- Between internal context functions that share type contracts
- In utility functions called by already-validated code

### Prefer Addition Over Modification

Extend interfaces without breaking existing consumers:

```elixir
# Good: Add optional fields to a context function
def start_transaction(charger_id, attrs, opts \\ []) do
  # opts: [notify: boolean, pre_authorize: boolean]
end

# Bad: Change the signature in a breaking way
# was: start_transaction(charger_id, attrs)
# now: start_transaction(charger_id, id_tag, meter_start)
# → breaks all existing callers
```

## OCPP-Specific Patterns

### Message Frame Shape

OCPP 1.6 JSON messages always follow this shape:

```
Call:       [2, UniqueId, Action, Payload]
CallResult: [3, UniqueId, Payload]
CallError:  [4, UniqueId, ErrorCode, ErrorDescription, ErrorDetails]
```

Parse and validate this frame shape before dispatching:

```elixir
defmodule ChargerStationsMs.OCPP.Message do
  @type call        :: {:call, id :: String.t(), action :: String.t(), payload :: map()}
  @type call_result :: {:call_result, id :: String.t(), payload :: map()}
  @type call_error  :: {:call_error, id :: String.t(), code :: String.t(), desc :: String.t()}
  @type t           :: call() | call_result() | call_error()

  @spec parse(list()) :: {:ok, t()} | {:error, :invalid_message}
  def parse([2, id, action, payload]), do: {:ok, {:call, id, action, payload}}
  def parse([3, id, payload]),         do: {:ok, {:call_result, id, payload}}
  def parse([4, id, code, desc, _]),   do: {:ok, {:call_error, id, code, desc}}
  def parse(_),                        do: {:error, :invalid_message}
end
```

### OCPI REST Endpoints

OCPI uses standard HTTP REST. Design endpoints following the OCPI 2.2.1 module specs:

```
GET  /ocpi/cpo/2.2.1/locations            → LocationsController.index
GET  /ocpi/cpo/2.2.1/locations/:id        → LocationsController.show
PUT  /ocpi/cpo/2.2.1/locations/:id        → LocationsController.update
GET  /ocpi/cpo/2.2.1/sessions             → SessionsController.index
GET  /ocpi/cpo/2.2.1/cdrs                 → CDRsController.index
```

Always version OCPI endpoints. Always validate the OCPI `Authorization` token at a plug before any module handler.

### DB Schema: OCPI-First From Day One

Design the DB schema to match the OCPI hierarchy even before implementing OCPI:

```
locations → evses → connectors
```

**Not:**
```
charge_points → connectors   # OCPP-only, hard to migrate later
```

This matters because OCPP's `ChargePoint → Connector` and OCPI's `Location → EVSE → Connector` are fundamentally different granularities. Designing OCPI-first from the start avoids a painful migration later.

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "We'll document the API later" | The typespecs ARE the documentation. Define them first. |
| "Internal context APIs don't need contracts" | Internal consumers are still consumers. Contracts prevent coupling. |
| "We don't need the OCPI schema yet" | The migration from OCPP-only schema to OCPI-aware schema is expensive. Do it now. |
| "Nobody uses that undocumented field" | Hyrum's Law: if it's observable, somebody will depend on it. |
| "OCPP 2.0.1 can wait" | True — but structure your code so the 1.6 handlers are isolated and swappable, not baked into every layer. |

## Red Flags

- Context functions that return different shapes depending on conditions
- Inconsistent error formats across context modules
- Validation scattered throughout internal code instead of at system boundaries
- `charge_points` table instead of `locations → evses → connectors`
- Missing `@spec` on public context functions
- OCPP message parsing mixed into the WebSocket handler instead of a dedicated parser module

## Verification

After designing an interface:

- [ ] Every public function has `@spec` and `@doc`
- [ ] Error responses follow a single consistent format (`{:ok, _} | {:error, _}`)
- [ ] Validation happens at system boundaries only (WebSocket, HTTP, LiveView events)
- [ ] DB schema follows OCPI hierarchy (`locations → evses → connectors`)
- [ ] OCPP message parsing is isolated in its own module
- [ ] New fields are additive and optional (backward compatible)
