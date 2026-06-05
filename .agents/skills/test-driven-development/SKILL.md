---
name: test-driven-development
description: Drives development with tests. Use when implementing any logic, fixing any bug, or changing any behavior. Use when you need to prove that code works, when a bug report arrives, or when you're about to modify existing functionality.
---

# Test-Driven Development

## Overview

Write a failing test before writing the code that makes it pass. For bug fixes, reproduce the bug with a test before attempting a fix. Tests are proof — "seems right" is not done. A codebase with good tests is an AI agent's superpower; a codebase without tests is a liability.

## When to Use

- Implementing any new logic or behavior
- Fixing any bug (the Prove-It Pattern)
- Modifying existing functionality
- Adding edge case handling
- Any change that could break existing behavior

**When NOT to use:** Pure configuration changes, documentation updates, or static content changes with no behavioral impact.

## The TDD Cycle

```
    RED                GREEN              REFACTOR
 Write a test    Write minimal code    Clean up the
 that fails  ──→  to make it pass  ──→  implementation  ──→  (repeat)
      │                  │                    │
      ▼                  ▼                    ▼
   Test FAILS        Test PASSES         Tests still PASS
```

### Step 1: RED — Write a Failing Test

Write the test first. It must fail. A test that passes immediately proves nothing.

```elixir
# RED: This test fails because handle_boot_notification/2 doesn't exist yet
defmodule ChargerStationsMs.OCPP.BootNotificationTest do
  use ChargerStationsMs.DataCase

  alias ChargerStationsMs.OCPP.MessageHandler

  describe "handle_boot_notification/2" do
    test "creates charger record and returns Accepted response" do
      charger_id = "CHARGER-001"
      payload = %{"chargePointModel" => "Model-X", "chargePointVendor" => "ACME"}

      assert {:ok, %{status: "Accepted"}} = MessageHandler.handle_boot_notification(charger_id, payload)
      assert charger = Repo.get_by(Charger, ocpp_id: charger_id)
      assert charger.model == "Model-X"
    end
  end
end
```

### Step 2: GREEN — Make It Pass

Write the minimum code to make the test pass. Don't over-engineer:

```elixir
# GREEN: Minimal implementation
def handle_boot_notification(charger_id, payload) do
  attrs = %{
    ocpp_id: charger_id,
    model: payload["chargePointModel"],
    vendor: payload["chargePointVendor"]
  }

  %Charger{}
  |> Charger.changeset(attrs)
  |> Repo.insert(on_conflict: :replace_all, conflict_target: :ocpp_id)
  |> case do
    {:ok, _charger} -> {:ok, %{status: "Accepted", current_time: DateTime.utc_now(), interval: 300}}
    {:error, changeset} -> {:error, changeset}
  end
end
```

### Step 3: REFACTOR — Clean Up

With tests green, improve the code without changing behavior:

- Extract shared logic
- Improve naming
- Remove duplication

Run tests after every refactor step to confirm nothing broke.

## The Prove-It Pattern (Bug Fixes)

When a bug is reported, **do not start by trying to fix it.** Start by writing a test that reproduces it.

```
Bug report arrives
       │
       ▼
  Write a test that demonstrates the bug
       │
       ▼
  Test FAILS (confirming the bug exists)
       │
       ▼
  Implement the fix
       │
       ▼
  Test PASSES (proving the fix works)
       │
       ▼
  Run full test suite (no regressions)
```

## The Test Pyramid

```
          ╱╲
         ╱  ╲         Integration Tests (~15-20%)
        ╱    ╲        Full WebSocket flows, DB-backed
       ╱──────╲
      ╱        ╲      Unit Tests (~80%)
     ╱          ╲     Pure logic, isolated, milliseconds each
    ╱────────────╲    (context functions, message parsing, etc.)
```

**The Beyonce Rule:** If you liked it, you should have put a test on it. Refactoring and migrations are not responsible for catching your bugs — your tests are.

### ExUnit Test Sizes

| Size | Constraints | Speed | Example |
|------|------------|-------|---------|
| **Unit** | No DB, no HTTP, pure logic | Milliseconds | OCPP message parser, CDR calculation |
| **Integration** | DB via `DataCase`, in-process | Seconds | Context functions, GenServer flows |
| **E2E** | Full WebSocket connection | Minutes | Charger connect → transaction → disconnect |

Use `DataCase` for DB-backed tests. Use `ConnCase` for HTTP/LiveView tests. Use plain `ExUnit.Case` for pure logic.

## Writing Good Tests with ExUnit

### Use `start_supervised!/1` for Processes

```elixir
# Always start processes via start_supervised! — it guarantees cleanup
setup do
  charger_server = start_supervised!({ChargerHandler, charger_id: "TEST-001"})
  {:ok, charger_server: charger_server}
end
```

### Never Use `Process.sleep/1` to Synchronize

```elixir
# BAD: Flaky timing-based wait
Process.sleep(100)
assert state.status == :connected

# GOOD: Use :sys.get_state to ensure the process has handled prior messages
_ = :sys.get_state(charger_pid)
assert state.status == :connected

# GOOD: Use Process.monitor + assert_receive for process termination
ref = Process.monitor(charger_pid)
assert_receive {:DOWN, ^ref, :process, ^charger_pid, :normal}
```

### DAMP Over DRY in Tests

Tests should be self-contained and readable. A test should tell a complete story without requiring the reader to trace through shared helpers.

```elixir
# DAMP: Each test is self-contained
test "rejects StartTransaction when charger is offline" do
  charger = charger_fixture(%{status: :offline})
  assert {:error, :charger_offline} = Sessions.start_transaction(charger.id, %{id_tag: "RFID-001"})
end

test "rejects StartTransaction when charger is already charging" do
  charger = charger_fixture(%{status: :charging})
  assert {:error, :charger_busy} = Sessions.start_transaction(charger.id, %{id_tag: "RFID-001"})
end
```

### Test State, Not Interactions

Assert on the *outcome* of an operation, not on which internal functions were called.

```elixir
# GOOD: Tests what the function does (state-based)
test "StopTransaction persists CDR to database" do
  session = session_fixture()
  {:ok, cdr} = Sessions.stop_transaction(session.id, %{meter_stop: 5000})

  assert cdr.energy_kwh == 5.0
  assert cdr.session_id == session.id
  refute is_nil(cdr.ended_at)
end

# BAD: Tests internal implementation details
test "StopTransaction calls CDR.create with correct params" do
  # Don't test internal function calls
end
```

### Naming Tests Descriptively

```elixir
# GOOD: Reads like a specification
describe "Sessions.start_transaction/2" do
  test "creates a session and returns the session ID"
  test "returns error when charger is offline"
  test "returns error when RFID tag is not authorized"
  test "is idempotent for duplicate StartTransaction from same charger"
end

# BAD: Vague names
describe "Sessions" do
  test "works"
  test "handles errors"
  test "test 3"
end
```

## Test Anti-Patterns to Avoid

| Anti-Pattern | Problem | Fix |
|---|---|---|
| `Process.sleep/1` for synchronization | Flaky timing-based tests | Use `:sys.get_state/1` or `assert_receive` |
| Testing implementation details | Tests break on refactoring | Test inputs and outputs, not internal structure |
| No test isolation | Tests pass individually, fail together | Each test sets up and tears down its own state |
| Mocking everything | Tests pass but production breaks | Use real implementations; mock only external HTTP calls |
| `assert_receive` without timeout | Hangs indefinitely | Always specify a timeout or use the default (100ms) |

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I'll write tests after the code works" | You won't. And tests written after the fact test implementation, not behavior. |
| "This is too simple to test" | Simple code gets complicated. The test documents the expected behavior. |
| "Tests slow me down" | Tests slow you down now. They speed you up every time you change the code later. |
| "I tested it manually" | Manual testing doesn't persist. Tomorrow's change might break it with no way to know. |
| "It's just a GenServer, testing is hard" | Test the GenServer's state transitions via `start_supervised!` and `:sys.get_state`. |

## Red Flags

- Writing code without any corresponding tests
- Tests that pass on the first run (they may not be testing what you think)
- Bug fixes without reproduction tests
- `Process.sleep/1` in tests (always flaky)
- Test names that don't describe the expected behavior
- Skipping tests to make the suite pass

## Verification

After completing any implementation:

- [ ] Every new behavior has a corresponding test
- [ ] All tests pass: `mix test`
- [ ] Bug fixes include a reproduction test that failed before the fix
- [ ] Test names describe the behavior being verified
- [ ] No tests were skipped or disabled
- [ ] `mix precommit` passes cleanly
