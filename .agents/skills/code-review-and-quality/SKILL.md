---
name: code-review-and-quality
description: Conducts multi-axis code review. Use before merging any change. Use when reviewing code written by yourself, another agent, or a human. Use when you need to assess code quality across multiple dimensions before it enters the main branch.
---

# Code Review and Quality

## Overview

Multi-dimensional code review with quality gates. Every change gets reviewed before merge — no exceptions. Review covers five axes: correctness, readability, architecture, security, and performance.

**The approval standard:** Approve a change when it definitely improves overall code health, even if it isn't perfect. Perfect code doesn't exist — the goal is continuous improvement. Don't block a change because it isn't exactly how you would have written it. If it improves the codebase and follows the project's conventions, approve it.

## When to Use

- Before merging any PR or change
- After completing a feature implementation
- When another agent or model produced code you need to evaluate
- When refactoring existing code
- After any bug fix (review both the fix and the regression test)

## The Five-Axis Review

Every review evaluates code across these dimensions:

### 1. Correctness

Does the code do what it claims to do?

- Does it match the spec or task requirements?
- Are edge cases handled (nil, empty list, boundary values)?
- Are error paths handled — not just the happy path (`{:ok, _}` but also `{:error, _}`)?
- Does it pass all tests? Are the tests actually testing the right things?
- For GenServers: are all message patterns handled? Will unmatched messages crash the process?
- For Ecto: are changesets validating what they should? Are all required fields cast?

### 2. Readability & Simplicity

Can another engineer (or agent) understand this code without the author explaining it?

- Are names descriptive and consistent with project conventions?
- Is the control flow straightforward — no deeply nested `with` chains that could be split?
- Are function clauses ordered logically (most specific first)?
- Are there any "clever" tricks that should be simplified?
- **Could this be done in fewer lines?** (1000 lines where 100 suffice is a failure)
- **Are abstractions earning their complexity?** (Don't generalize until the third use case)
- Are there dead code artifacts: unused variables, commented-out code, no-op functions?

### 3. Architecture

Does the change fit the system's design?

- Does it follow the Phoenix context boundaries? (Business logic in contexts, not in LiveViews)
- Does it maintain the supervision tree structure? (New processes should be supervised)
- Are OCPP message handlers isolated from OCPI integration code?
- Is the DB schema following the `locations → evses → connectors` hierarchy?
- Does it introduce circular dependencies between contexts?

### 4. Security

Does the change introduce vulnerabilities?

- Is user input validated at system boundaries (WebSocket handlers, HTTP controllers, LiveView events)?
- Are secrets kept out of code, logs, and version control?
- Are Ecto queries parameterized (no string interpolation into raw SQL)?
- Are OCPI authentication tokens validated before any module handler?
- Is user-controlled data used in `String.to_atom/1`? (Memory leak risk — never do this)
- Are Stripe webhook signatures verified before processing?

### 5. Performance

Does the change introduce performance problems?

- Are there N+1 query patterns? (Accessing `charger.sessions` in a loop without preloading)
- Are associations preloaded when they'll be accessed in templates?
- Are there unbounded queries? (Missing `limit` on large tables)
- Are there blocking operations in a GenServer's `handle_call`? (Should be async)
- Are MeterValues being persisted individually per message, or batched?

## Change Sizing

Small, focused changes are easier to review, faster to merge, and safer. Target these sizes:

```
~100 lines changed   → Good. Reviewable in one sitting.
~300 lines changed   → Acceptable if it's a single logical change.
~1000 lines changed  → Too large. Split it.
```

**Splitting strategies when a change is too large:**

| Strategy | How | When |
|----------|-----|------|
| **Vertical** | Break into smaller full-stack slices | Feature work |
| **Horizontal** | Schema/migration first, then context, then LiveView | Layered architecture |
| **By concern** | Refactoring separate from feature addition | Mixed changes |

**Separate refactoring from feature work.** A change that refactors existing code and adds new behavior is two changes — submit them separately.

## Review Process

### Step 1: Understand the Context

Before looking at code, understand the intent:

```
- What is this change trying to accomplish?
- What spec or task does it implement?
- What is the expected behavior change?
```

### Step 2: Review the Tests First

Tests reveal intent and coverage:

```
- Do tests exist for the change?
- Do they use `start_supervised!` for processes?
- Are there any `Process.sleep/1` calls? (Red flag)
- Do tests have descriptive names?
- Would the tests catch a regression if the code changed?
```

### Step 3: Review the Implementation

Walk through the code with the five axes in mind.

### Step 4: Categorize Findings

Label every comment with its severity so the author knows what's required vs optional:

| Prefix | Meaning | Author Action |
|--------|---------|---------------|
| *(no prefix)* | Required change | Must address before merge |
| **Critical:** | Blocks merge | Security vulnerability, data loss, broken functionality |
| **Nit:** | Minor, optional | Author may ignore — formatting, style preferences |
| **Optional:** / **Consider:** | Suggestion | Worth considering but not required |
| **FYI** | Informational only | No action needed — context for future reference |

### Step 5: Verify the Verification

Check the author's verification story:

```
- What tests were run? (`mix test` output)
- Did `mix precommit` pass?
- Was the change tested manually (e.g., connected a real charger)?
```

## Honesty in Review

- **Don't rubber-stamp.** "LGTM" without evidence of review helps no one.
- **Don't soften real issues.** "This might be a minor concern" when it's a security bug is dishonest.
- **Quantify problems when possible.** "This N+1 query will add ~50ms per charger in the fleet list" is better than "this could be slow."
- **Push back on approaches with clear problems.** Sycophancy is a failure mode.
- **Accept override gracefully.** If the author has full context and disagrees, defer. Comment on code, not people.

## Dead Code Hygiene

After any refactoring or implementation change, check for orphaned code:

```
DEAD CODE IDENTIFIED:
- old_handle_boot_notification/2 in ChargerHandler — replaced by MessageHandler.handle/2
- LegacyCharger schema in chargers.ex — unused after migration
→ Safe to remove these?
```

Don't silently delete things you're not sure about. When in doubt, ask.

## The Review Checklist

```markdown
## Review: [PR/Change title]

### Context
- [ ] I understand what this change does and why

### Correctness
- [ ] Change matches spec/task requirements
- [ ] Edge cases handled (nil, empty, boundary values)
- [ ] Error paths handled ({:error, _} cases)
- [ ] All OCPP message patterns handled in GenServer
- [ ] Tests cover the change adequately

### Readability
- [ ] Names are clear and consistent with Elixir conventions
- [ ] Logic is straightforward — no unnecessary `with` nesting
- [ ] No unnecessary complexity or premature abstraction

### Architecture
- [ ] Business logic in contexts, not in LiveViews or controllers
- [ ] New processes are supervised
- [ ] Context boundaries are respected (OCPP ≠ OCPI ≠ Billing)
- [ ] DB schema follows OCPI hierarchy

### Security
- [ ] No secrets in code
- [ ] Input validated at system boundaries
- [ ] No `String.to_atom/1` on user-controlled data
- [ ] Auth checks in place for protected routes

### Performance
- [ ] No N+1 queries (associations preloaded when needed)
- [ ] No blocking operations in GenServer handle_call
- [ ] Bounded queries (limit on large tables)

### Verification
- [ ] `mix test` passes
- [ ] `mix precommit` passes
- [ ] Manual verification done if applicable

### Verdict
- [ ] **Approve** — Ready to merge
- [ ] **Request changes** — Issues must be addressed
```

## Common Rationalizations

| Rationalization | Reality |
|---|---|
| "It works, that's good enough" | Working code that's unreadable, insecure, or architecturally wrong creates debt that compounds. |
| "AI-generated code is probably fine" | AI code needs more scrutiny, not less. It's confident and plausible, even when wrong. |
| "The tests pass, so it's good" | Tests are necessary but not sufficient. They don't catch architecture problems or security issues. |
| "We'll clean it up later" | Later never comes. The review is the quality gate — use it. |

## Red Flags

- PRs merged without any review
- Review that only checks if tests pass (ignoring other axes)
- Security-sensitive changes without security-focused review
- Large PRs that are "too big to review properly" (split them)
- No regression tests with bug fix PRs
- `Process.sleep/1` in tests passing review
- `String.to_atom/1` on user input passing review

## Verification

After review is complete:

- [ ] All Critical issues are resolved
- [ ] All Important issues are resolved or explicitly deferred with justification
- [ ] `mix test` passes
- [ ] `mix precommit` passes
- [ ] The verification story is documented
