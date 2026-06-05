---
name: debugging-and-error-recovery
description: Guides systematic root-cause debugging. Use when tests fail, builds break, behavior doesn't match expectations, or you encounter any unexpected error. Use when you need a systematic approach to finding and fixing the root cause rather than guessing.
---

# Debugging and Error Recovery

## Overview

Systematic debugging with structured triage. When something breaks, stop adding features, preserve evidence, and follow a structured process to find and fix the root cause. Guessing wastes time. The triage checklist works for test failures, build errors, runtime bugs, and OTP process crashes.

## When to Use

- Tests fail after a code change
- The build breaks
- Runtime behavior doesn't match expectations
- A GenServer crashes or restarts unexpectedly
- An error appears in logs
- Something worked before and stopped working

## The Stop-the-Line Rule

When anything unexpected happens:

```
1. STOP adding features or making changes
2. PRESERVE evidence (error output, logs, repro steps)
3. DIAGNOSE using the triage checklist
4. FIX the root cause
5. GUARD against recurrence
6. RESUME only after verification passes
```

**Don't push past a failing test or broken build to work on the next feature.** Errors compound. A bug in Step 3 that goes unfixed makes Steps 4-10 wrong.

## The Triage Checklist

Work through these steps in order. Do not skip steps.

### Step 1: Reproduce

Make the failure happen reliably. If you can't reproduce it, you can't fix it with confidence.

For test failures:
```bash
# Run the specific failing test
mix test test/path/to/specific_test.exs

# Run with verbose output
mix test --trace

# Run in isolation to rule out test pollution
mix test test/path/to/specific_test.exs:42

# Run previously failed tests
mix test --failed
```

For GenServer crashes, check the supervisor log first:
```elixir
# In IEx: check what the supervisor saw
Process.whereis(ChargerStationsMs.OCPP.ChargerSupervisor)
Supervisor.which_children(ChargerStationsMs.OCPP.ChargerSupervisor)
```

### Step 2: Localize

Narrow down WHERE the failure happens:

```
Which layer is failing?
├── OCPP message parsing   → Check the raw WebSocket frame
├── GenServer handler      → Check the crash reason via :sys.get_state or logs
├── Context/business logic → Check the function return value
├── Ecto/Database          → Check the changeset errors or query
├── LiveView               → Check the socket assigns and event handler
├── External service       → Check HTTP response from Stripe / OCPI partner
└── Test itself            → Check if the test is correctly written
```

**For OTP process crashes specifically:**
```elixir
# Check why a process died
# In the supervisor logs, look for:
# [error] GenServer ChargerHandler terminating
# ** (MatchError) no match of right hand side value: ...
#    last message: {:call, {<pid>, ref}, :get_state}
#    state: %{charger_id: "CHARGER-001", ...}

# Use :sys.get_state to inspect a live GenServer
:sys.get_state(pid)

# Trace calls to a process
:sys.trace(pid, true)
```

### Step 3: Reduce

Create the minimal failing case:

- Remove unrelated setup code until only the bug remains
- Simplify the OCPP payload to the smallest example that triggers the failure
- Strip the test to the bare minimum that reproduces the issue

A minimal reproduction makes the root cause obvious and prevents fixing symptoms.

### Step 4: Fix the Root Cause

Fix the underlying issue, not the symptom:

```
Symptom: "GenServer crashes when charger sends a MeterValues message"

Symptom fix (bad):
  → Wrap the handler in try/rescue and log the error

Root cause fix (good):
  → The sampled_value field is sometimes nil, but the pattern match
     assumes it's always a list. Fix the parser to handle nil.
```

Ask: "Why does this happen?" until you reach the actual cause, not just where it manifests.

**OTP-specific root cause patterns:**

| Symptom | Likely root cause |
|---------|------------------|
| GenServer crash on message | Unhandled pattern match in `handle_cast/handle_call` |
| Process exits with `:normal` unexpectedly | `GenServer.stop/1` called or `{:stop, :normal, state}` returned |
| Registry lookup returns `nil` | Process wasn't started or crashed before lookup |
| Message queue growing | Slow `handle_info` or unmatched messages accumulating |
| Timeout on `GenServer.call` | Blocking operation in handle_call, or process is dead |

### Step 5: Guard Against Recurrence

Write a test that catches this specific failure:

```elixir
# The bug: MeterValues with nil sampled_value crashed the handler
test "handles MeterValues with nil sampled_value gracefully" do
  charger = start_supervised!({ChargerHandler, charger_id: "TEST-001"})

  msg = %{
    "transactionId" => 1,
    "meterValue" => [%{"sampledValue" => nil}]
  }

  # Should not crash
  assert :ok = ChargerHandler.handle_meter_values(charger, msg)
end
```

This test will prevent the same bug from recurring. It should fail without the fix and pass with it.

### Step 6: Verify End-to-End

After fixing, verify the complete scenario:

```bash
# Run the specific test
mix test test/path/to/specific_test.exs

# Run the full test suite (check for regressions)
mix test

# Run the precommit checks
mix precommit
```

## OTP-Specific Debugging Patterns

### Inspect Live Process State

```elixir
# Get the state of a GenServer by PID
:sys.get_state(pid)

# Get state by registered name
:sys.get_state(ChargerStationsMs.OCPP.ChargerRegistry)

# Get statistics about a process
:sys.statistics(pid, :get)
```

### Monitor for Crashes in Tests

```elixir
test "charger handler restarts after crash" do
  pid = start_supervised!({ChargerHandler, charger_id: "TEST-001"})
  ref = Process.monitor(pid)

  # Force a crash
  Process.exit(pid, :kill)

  # Wait for the DOWN message
  assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

  # Supervisor should restart it
  :timer.sleep(50)
  assert Process.whereis(:"charger:TEST-001") != nil
end
```

### Trace Message Flow

```elixir
# Enable tracing for a GenServer (useful in IEx during development)
:sys.trace(pid, true)

# Send a message and watch the trace output
GenServer.cast(pid, {:ocpp_message, boot_notification_payload})

# Disable tracing
:sys.trace(pid, false)
```

## Safe Fallback Patterns

When under time pressure, use safe fallbacks:

```elixir
# Safe default + warning (instead of crashing)
def parse_sampled_value(nil), do: {:ok, []}
def parse_sampled_value(values) when is_list(values), do: {:ok, values}
def parse_sampled_value(other) do
  Logger.warning("Unexpected sampled_value format: #{inspect(other)}")
  {:ok, []}
end

# Don't crash the handler on bad input — log and continue
def handle_cast({:ocpp_message, payload}, state) do
  case process_message(payload, state) do
    {:ok, new_state} -> {:noreply, new_state}
    {:error, reason} ->
      Logger.error("Failed to process OCPP message from #{state.charger_id}: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "I know what the bug is, I'll just fix it" | You might be right 70% of the time. The other 30% costs hours. Reproduce first. |
| "The failing test is probably wrong" | Verify that assumption. If the test is wrong, fix the test. Don't just skip it. |
| "OTP will restart it, so it's fine if it crashes" | Supervision is for unexpected faults, not expected bad input. Handle known error cases explicitly. |
| "I'll fix it in the next commit" | Fix it now. The next commit will introduce new bugs on top of this one. |
| "This is a flaky test, ignore it" | Flaky tests mask real bugs. Fix the flakiness or understand why it's intermittent. |

## Red Flags

- Skipping a failing test to work on new features
- Guessing at fixes without reproducing the bug
- Wrapping crashes in `try/rescue` as a fix (masks the root cause)
- "It works now" without understanding what changed
- No regression test added after a bug fix
- Multiple unrelated changes made while debugging

## Verification

After fixing a bug:

- [ ] Root cause is identified and documented
- [ ] Fix addresses the root cause, not just symptoms
- [ ] A regression test exists that fails without the fix
- [ ] All existing tests pass (`mix test`)
- [ ] Build succeeds (`mix compile --warnings-as-errors`)
- [ ] `mix precommit` passes
- [ ] The original bug scenario is verified end-to-end
