---
name: rc-plan
description: Plan code changes, bug fixes, and feature implementations from a prompt. Investigates the actual codebase first, then interrogates scope in one batched round — what's in, what's out, and which tradeoffs are acceptable — before drafting a plan saved to ~/.claude/plans/. The plan is the deliverable; never implements. Use when Ray asks to plan a change, scope a fix, design an approach, or think through an implementation before building it.
allowed-tools: Read, Glob, Grep, Bash, Write, Edit, AskUserQuestion
user-invocable: true
---

# Plan

You are planning, not implementing. The deliverable is a plan document that
works as an architectural decision record — something a fresh session can
pick up and execute from. **Do not write or edit any code, do not commit,
do not create branches.** The only files you touch live in
`~/.claude/plans/`.

## Input

The prompt: what Ray wants to change, fix, or build — as the argument to
`/rc-plan` or from earlier in the conversation. If there's no prompt, ask.
If it's too vague to even start investigating ("fix the auth thing"), ask
what it refers to before reading anything.

## Step 1: Investigate the Codebase

Ground the plan in code that actually exists. Read the files the change
would touch, trace the affected paths, find the existing patterns the work
must fit. A plan built on guessed file layouts is worthless — every claim
about current behavior in the plan must carry a `file:line` reference, and
anything you couldn't verify gets marked as unverified, not stated as fact.

For bug fixes, start with symptoms. If the prompt has no reproduction,
error message, or log line, ask for the artifact that pinpoints it (stack
frame, request/response payload, log excerpt) instead of theorizing from
code reading. That question goes into the Step 2 batch, not a separate
round.

## Step 2: Scope Interrogation — Mandatory

Never skip this step, even when the ask seems obvious. An ask that seems
simple is a red flag, not a green light. All questions go in **one batched
round** — not one at a time, not mid-drafting. Use AskUserQuestion when the
options are enumerable; free text where they aren't.

Always cover acceptability — what's acceptable and what's not:

1. **Outcome bar.** Root-cause fix only, or is a mitigation acceptable for
   now? If a workaround is fine, does it need a tracked follow-up?
2. **Scope boundary.** What's explicitly out: adjacent cleanup, refactors,
   related bugs surfaced during investigation, "while we're in here"
   improvements. Name the specific temptations you found in Step 1 and ask
   whether each is in or out.
3. **Acceptable tradeoffs.** Behavior changes visible to users, breaking
   API changes, schema migrations, performance regressions, dropped edge
   cases. For each tradeoff the approach might force, ask — don't assume.
4. **Blast radius.** What must not break under any circumstance? How much
   risk is tolerable in the parts that may change?
5. **Constraints.** Compatibility requirements, patterns to follow or
   avoid, deadline pressure that changes the right answer.

Plus anything genuinely ambiguous from the investigation. Skip questions
the prompt or the code already answers — the batch should be sharp, not a
checklist recital. One round; a second only if an answer opens something
new that changes the plan's shape.

## Step 3: Draft the Plan

Save to `~/.claude/plans/` with a filename built from date, location, and
subject:

- Not in a git repo: `dd-mm-yyyy-<subject>.md`
- In a repo: `dd-mm-yyyy-<repo>-<subject>.md`
- In a monorepo subpackage: `dd-mm-yyyy-<repo>-<package>-<subject>.md`

Where:

- **date** — today via `date +%d-%m-%Y`.
- **repo** — basename of `git rev-parse --show-toplevel`.
- **package** — set when the working directory is inside
  `<repo-root>/packages/<package>/`; it's that directory's name.
- **subject** — a short kebab-case slug you pick that names the work
  (e.g. `replica-skip`, `webhook-retries`). Distinctive over generic:
  `fix-bug` never; the thing being fixed, always. Plans that record a
  review rather than upcoming work (e.g. saved by rc-adversarial-review)
  prefix the subject with `review-`: `review-webhook-retries`.

If a plan for this same work already exists, update it in place — don't
create a sibling.

Template — omit sections with nothing real to say:

```markdown
# <Title — the change in one line>

**Status:** planned, not started. <Where work happens: branch/worktree,
how it ends — PR via rc-pr-open, direct commit, etc.>

## Intent

What problem this solves and for whom. Alternatives considered and
deliberately dropped, in a sentence each.

## Current state (verified in code)

What exists today, with `file:line` references. Only what you actually
read — mark anything unverified.

## Scope

**In:** what this touches.
**Out:** what it deliberately doesn't — including Ray's explicit
exclusions from the interrogation.

## Design decisions

Numbered. Each records the decision, the why, and any accepted tradeoff
in Ray's terms ("Accepted tradeoff: not placement-aware — documented,
not solved here"). These come straight from the Step 2 answers; they are
the contract for the implementation.

## Edge cases

What happens when things go wrong, and what the plan does about each.

## Risks & blind spots

What could bite, and what this plan has NOT considered — unknowns you
couldn't resolve, areas you didn't investigate, assumptions that could
be wrong. An empty section here means you didn't look hard enough.

## Implementation

Ordered steps, each small enough to verify. Name the files each step
touches.

## Verification

How to prove it works: commands, test cases to add, manual checks.

## Open questions

Anything still unresolved, phrased so Ray can answer fast.
```

Sizing: proportional to the work. A one-file bug fix gets a one-screen
plan; don't pad small work into big documents.

## Step 4: Present

After writing, present:

```
## Plan Saved

- `~/.claude/plans/<dd-mm-yyyy-...-subject>.md`

### Approach
- (2–4 bullets: the shape of the solution)

### Decisions locked in
- (the acceptability answers from Step 2 — what Ray ruled in and out)

### Open questions
- (anything still needing an answer before implementation starts)
```

Then stop. Implementation starts only when Ray says so, and may happen in
a different session pointed at the plan file.

## Keep the Plan Accurate

If Ray changes direction while the session continues — during the
interrogation, after presenting, mid-discussion — update the plan file to
match. A stale plan is worse than no plan: the next session will trust it.
