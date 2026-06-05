---
name: idea-refine
description: Refines ideas iteratively. Use when you have a rough concept that needs sharpening before writing a spec. Use to explore design decisions, evaluate trade-offs, or stress-test a plan before committing to it.
---

# Idea Refine

Refines raw ideas into sharp, actionable concepts worth building through structured divergent and convergent thinking.

## How It Works

1. **Understand & Expand (Divergent):** Restate the idea, ask sharpening questions, and generate variations.
2. **Evaluate & Converge:** Cluster ideas, stress-test them, and surface hidden assumptions.
3. **Sharpen & Ship:** Produce a concrete markdown one-pager moving work forward.

## Philosophy

- Simplicity is the ultimate sophistication. Push toward the simplest version that still solves the real problem.
- Start with the user experience, work backwards to technology.
- Challenge every assumption. "How it's usually done" is not a reason.
- **Be honest, not supportive.** If an idea is weak, say so with kindness. A good ideation partner is not a yes-machine. Push back on complexity, question real value.

## Process

### Phase 1: Understand & Expand (Divergent)

**Goal:** Take the raw idea and open it up.

1. **Restate the idea** as a crisp "How Might We" problem statement. This forces clarity on what's actually being solved.

2. **Ask 3-5 sharpening questions** — no more. Focus on:
   - Who is this for, specifically?
   - What does success look like?
   - What are the real constraints (time, tech, resources)?
   - What's been tried before?
   - Why now?

3. **Generate 5-8 idea variations** using these lenses:
   - **Inversion:** "What if we did the opposite?"
   - **Constraint removal:** "What if budget/time/tech weren't factors?"
   - **Simplification:** "What's the version that's 10x simpler?"
   - **Audience shift:** "What if this were for a different user?"
   - **10x version:** "What would this look like at massive scale?"

   Push beyond what was initially asked for. Create solutions people don't know they need yet.

### Phase 2: Evaluate & Converge

After the initial exploration, shift to convergent mode:

1. **Cluster** the ideas that resonated into 2-3 distinct directions. Each direction should feel meaningfully different.

2. **Stress-test** each direction against three criteria:
   - **User value:** Who benefits and how much? Is this a painkiller or a vitamin?
   - **Feasibility:** What's the technical cost? What's the hardest part?
   - **Differentiation:** What makes this genuinely different from the existing approach?

3. **Surface hidden assumptions.** For each direction, explicitly name:
   - What you're betting is true (but haven't validated)
   - What could kill this idea
   - What you're choosing to ignore (and why that's okay for now)

### Phase 3: Sharpen & Ship

Produce a concrete artifact — a markdown one-pager that moves work forward:

```markdown
# [Idea Name]

## Problem Statement
[One-sentence "How Might We" framing]

## Recommended Direction
[The chosen direction and why — 2-3 paragraphs max]

## Key Assumptions to Validate
- [ ] [Assumption 1 — how to test it]
- [ ] [Assumption 2 — how to test it]

## MVP Scope
[The minimum version that tests the core assumption. What's in, what's out.]

## Not Doing (and Why)
- [Thing 1] — [reason]
- [Thing 2] — [reason]

## Open Questions
- [Question that needs answering before building]
```

**The "Not Doing" list is often the most valuable part.** Focus is about saying no to good ideas. Make the trade-offs explicit.

Save the output to `docs/ideas/[idea-name].md` (confirm with the user first).

## Library Ideation Considerations

When ideating on phoenix_notifications features, consider:

- **Monolith-first:** Most Phoenix apps are monoliths — do not design defaults around microservice or Kafka patterns
- **DX is the product:** The install experience, the first working example, and the escape hatches matter as much as the feature itself
- **Public API is a contract:** Every function and option added to the public surface is a backwards-compatibility obligation — prefer fewer, more composable primitives
- **Component vs. behaviour:** Decide early whether a feature belongs in the LiveComponent (UI state) or in the user's app (business logic); never blur this line
- **Hex ecosystem:** Check if a dependency is already widely used in Phoenix apps before adding it; minimise the dependency footprint

## Anti-patterns to Avoid

- **Don't generate 20+ ideas.** Quality over quantity. 5-8 well-considered variations beat 20 shallow ones.
- **Don't be a yes-machine.** Push back on weak ideas with specificity and kindness.
- **Don't skip "who is this for."** Every good idea starts with a person and their problem.
- **Don't produce a plan without surfacing assumptions.** Untested assumptions are the #1 killer of good ideas.
- **Don't jump to Phase 3 without running Phases 1 and 2.**

## Red Flags

- Jumping straight to implementation without exploring alternatives
- No "Not Doing" list — means trade-offs haven't been made explicit
- "Obviously we should..." without stating the assumption being made
- No assumptions listed before committing to a direction
- Yes-machining weak ideas instead of pushing back

## Verification

After completing an ideation session:

- [ ] A clear "How Might We" problem statement exists
- [ ] The target user and success criteria are defined
- [ ] Multiple directions were explored, not just the first idea
- [ ] Hidden assumptions are explicitly listed with validation strategies
- [ ] A "Not Doing" list makes trade-offs explicit
- [ ] The output is a concrete artifact (markdown one-pager), not just conversation
- [ ] The user confirmed the final direction before any implementation work begins
