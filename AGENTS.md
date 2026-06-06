# phx_notifications

A drop-in, self-contained **in-app notification system for Phoenix**, shipped as a library.
Elixir-first, Phoenix-optional: the core needs only Ecto + PubSub; the Bell LiveComponent,
the action endpoint, and out-of-app transports are optional add-ons that compile only when
their dependency is present.

This is a **dependency, not an application** — there is no endpoint, router, asset bundle, or
auth of our own. Guidance written for Phoenix *apps* (Layouts, core_components, `phx.gen.auth`,
asset pipelines) does not apply here.

---

## Agent Skills

Structured engineering workflows live in `.agents/skills/`. Reference the relevant skill at the
start of each phase — do not load all skills at once.

### Five Non-Negotiables (always active)

1. **Surface assumptions before building.** State what you are assuming and ask for correction before writing any code.
2. **Stop and ask when requirements conflict.** Name the specific conflict; do not guess or silently pick one interpretation.
3. **Push back when warranted.** You are not a yes-machine. State the problem clearly, propose an alternative, then respect the final decision.
4. **Prefer the boring, obvious solution.** A staff engineer should see the code and say "of course." Cleverness is expensive.
5. **Touch only what you are asked to touch.** No unsolicited refactors, no "while I'm here" scope creep, no removing things you don't fully understand.

### Skill Routing

| Situation | Skill |
|---|---|
| Vague idea needs sharpening | `.agents/skills/idea-refine/SKILL.md` |
| Starting a feature or significant change | `.agents/skills/spec-driven-development/SKILL.md` |
| Have a spec, need a task-by-task plan | `.agents/skills/planning-and-task-breakdown/SKILL.md` |
| Implementing multi-file changes | `.agents/skills/incremental-implementation/SKILL.md` |
| Writing or running tests | `.agents/skills/test-driven-development/SKILL.md` |
| Designing module boundaries / behaviours / public API | `.agents/skills/api-and-interface-design/SKILL.md` |
| Something broke — systematic root-cause triage | `.agents/skills/debugging-and-error-recovery/SKILL.md` |
| Reviewing code before merge | `.agents/skills/code-review-and-quality/SKILL.md` |
| Security-sensitive work (action tokens, recipient scoping) | `.agents/skills/security-and-hardening/SKILL.md` |
| Recording an architectural decision | `.agents/skills/documentation-and-adrs/SKILL.md` |

---

## Project guidelines

- Run `mix precommit` when you are done with all changes and fix any pending issues. It runs
  `compile --warnings-as-errors`, `format --check-formatted`, and `test`.
- **Never write a date or timestamp into any file without first checking the real current time.**
  Do not assume or guess the date — wrong dates in committed files are permanent.
- Design docs live in `docs/` (`docs/ideas/`, `docs/plans/`); usage guides in `guides/`.

## Library design rules (deliberate — do not "fix")

These choices are intentional; do not refactor them away without being asked:

- **The Bell is a `LiveComponent` on purpose.** The general advice to "avoid LiveComponents"
  does not apply — a self-contained, drop-in widget is exactly the strong, specific need that
  justifies one. Because a LiveComponent cannot receive PubSub directly, `PhxNotifications.LiveView`
  (an `on_mount` hook) forwards broadcasts to it via `send_update/3`.
- **Dependencies stay optional and minimal.** `ecto_sql`, `phoenix_pubsub`, `plug_crypto`, and
  `jason` are the only required deps. `phoenix_live_view`, `plug`, and `oban` are `optional: true`
  and their modules are guarded with `Code.ensure_loaded?/1`. Never add a *required* dependency
  without explicit agreement.
- **Behaviours over hardcoding.** Delivery destinations (`Transport`), delivery strategy
  (`Delivery`), and action logic (`ActionHandler`) are behaviours with shipped defaults. New
  capabilities are new adapters, not changes to the public API.
- **The notification list is a bounded plain assign** (`limit`), not a LiveView stream. This is
  acceptable given the bound; revisit only if unbounded growth becomes a real concern.
- **Default markup uses an emoji bell, not `<.icon>`/heroicons** — we cannot assume the host app
  has heroicons installed. Custom icons go through the `<:trigger>` slot.
- **`PhxNotifications.Migration.change/1` is the single source of truth** for the table schema and
  is dogfooded by the test migration. Schema changes go there.

---

## Elixir guidelines

- Elixir lists **do not support index based access** via `mylist[i]`. Use `Enum.at/2`, pattern
  matching, or the `List` module.
- Variables are immutable but rebindable, so for `if`/`case`/`cond` you **must** bind the result
  to a variable; you cannot rebind inside the expression:

      socket =
        if connected?(socket) do
          assign(socket, :val, val)
        end

- **Never** nest multiple modules in the same file (cyclic dependency / compile errors).
- **Never** use map access syntax (`struct[:field]`) on structs — they don't implement Access.
  Use `struct.field` or `Ecto.Changeset.get_field/2` for changesets.
- The standard library covers date/time (`Time`, `Date`, `DateTime`, `Calendar`). **Never** add a
  dependency unless asked.
- Don't use `String.to_atom/1` on user input (memory leak risk).
- Predicate names should not start with `is_` and should end in `?`. Reserve `is_*` for guards.
- OTP primitives like `DynamicSupervisor`/`Registry` require names in the child spec.
- Use `Task.async_stream/3` for concurrent enumeration with back-pressure (usually `timeout: :infinity`).

## Mix guidelines

- Read task docs/options first with `mix help task_name`.
- Debug test failures with `mix test test/my_test.exs` or `mix test --failed`.
- `mix deps.clean --all` is almost never needed — avoid it.

## Test guidelines

- Use `start_supervised!/1` to start processes in tests (guarantees cleanup).
- **Avoid** `Process.sleep/1` / `Process.alive?/1`. To wait on a process, use `Process.monitor/1`
  and assert on the `:DOWN` message; to synchronize, use `_ = :sys.get_state(pid)`.
- The suite runs against a SQLite test repo with no external services. Tests are serial
  (`async: false`) over a single connection; each clears state in `setup`.

## Ecto guidelines

- `Ecto.Schema` fields use `:string` even for `:text` columns.
- Access changeset fields with `Ecto.Changeset.get_field/2`.
- Fields set **programmatically** (e.g. `recipient_id`, `recipient_type`) should be set explicitly
  by the library, not driven by external user params through `cast`.
- `Ecto.Changeset.validate_number/2` does **not** support an `:allow_nil` option.
- Always `import Ecto.Query` where you build queries.

## HEEx / Phoenix HTML guidelines

- Templates always use `~H` (or `.html.heex`), never `~E`.
- Elixir has no `else if`/`elsif`. Use `cond` or `case` for multiple conditionals.
- Interpolate with `{...}` in tag attributes **and** tag bodies; use `<%= ... %>` only for block
  constructs (`if`/`cond`/`case`/`for`) within tag bodies.
- Class attributes use **list** syntax for conditionals, with `if(...)` wrapped in parens:

      <a class={["px-2 text-white", @flag && "py-5", if(@cond, do: "a", else: "b")]}>Text</a>

- Generate collections with `<%= for item <- @collection do %>` (or `:for={}`), never `Enum.each`.
- HEEx comments use `<%!-- comment --%>`.
