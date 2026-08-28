---
name: rc-loop
description: Full dev pipeline in one command — rc-plan (with batched scope interrogation) → Ray approves the plan → implement → rc-refactor → rc-adversarial-review to confidence 9+ → stop and report. Plan approval is the single human gate; after it, stages flow without pausing. Coordinates with other agents that may be working on the same branch — announces its files, and blocks the whole-branch refactor/review stages until every other agent communicates it is done. Any stage can be skipped by name — "skip refactor", "skip review", "skip codex" (passed into review) — and an existing plan path resumes mid-pipeline. Use when Ray asks to run the loop, the full pipeline, or plan-build-review a task end to end. Not the built-in /loop interval runner.
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, Skill, Agent, Workflow, ListAgents, SendMessage, AskUserQuestion
---

# The Loop

Run Ray's whole dev cycle on one prompt: plan it, get the plan approved,
build it, consolidate it, adversarially review it until confidence ≥ 9,
stop, report. **Plan approval is the only human gate.** Before it, rc-plan's
interrogation runs in full. After it, the pipeline flows — no pausing for
confirmation between stages, no "shall I proceed".

The sub-skills do the heavy lifting. This skill sequences them, holds the
one gate, keeps pipeline state in the plan file, and coordinates with other
agents on the branch.

## Pipeline Overrides

Each stage loads its sub-skill via the Skill tool and follows it as written,
**except** these enumerated overrides. Nothing else in any sub-skill is
overridden — their internal rules, honesty requirements, and revert policies
all stand.

1. **rc-plan's terminal stop** ("Then stop. Implementation starts only when
   Ray says so") → replaced by this pipeline's approval gate in Stage 1.
   Present the plan, wait for Ray's explicit approval, then continue here.
2. **rc-refactor's candidate-approval wait** ("Wait for Ray's approval. Do
   not edit a single file before it arrives") → present the full candidate
   list for the record, then proceed immediately. Ray approved this
   autonomy when he approved the plan. The skill's own restraint rules do
   the gatekeeping: when unsure whether duplication is real, leave it and
   note it.
3. **rc-refactor's verification-on-request rule** ("Do not run typecheck or
   the test suite on your own") → run verification immediately after the
   extractions land. A failing test after a pure refactor still means
   reverting that extraction, per the skill's own rule.

rc-adversarial-review needs no overrides — it already runs autonomously to
9+ and saves its own review plan.

## Stage 0: Preflight

1. Parse the arguments:
   - **Skip flags** (composable with either form below): Ray can skip any
     stage by name. `skip refactor` — skip Stage 5 (the barrier still runs
     before review, which is also whole-branch); `skip review` — skip
     Stage 6 and go straight to the report (which then carries no confidence
     score — say so, don't invent one); `skip codex` — run Stage 6 but pass
     the flag through to rc-adversarial-review. Skipping both refactor and
     review also skips the barrier — nothing whole-branch runs. Every
     skipped stage is marked "skipped on request" in the state section and
     the report; a skip is never inferred, only taken from Ray's words.
   - **Existing plan** — a path into `~/.claude/plans/`, or a prompt that
     names one ("continue the webhook-retries plan"): this is a resume. Read
     the plan; if it has a `## Pipeline` section, continue from the recorded
     stage; if not, start at Stage 2 with the plan as already-approved.
     Confirm the working tree matches what the state section claims before
     building on it.
   - **A prompt** — fresh run, start at Stage 1.
   - **Nothing** — ask Ray what to build before touching anything.
2. Confirm this is a git repo. Without git there is no diff base for
   refactor or review — say so and stop rather than improvising.
3. Record the current branch and `git log -1 --oneline` — the baseline for
   spotting other agents' work later.

## Stage 1: Plan

Invoke `Skill(rc-plan)` with the prompt. It runs in full — codebase
investigation, the mandatory batched interrogation round, the saved plan
document.

Then the gate: present the plan and wait for Ray's explicit approval. Amend
and re-present until he gives it (keeping the plan file current as direction
changes, per rc-plan's own rule). Approval means everything from Stage 2
through Stage 7 runs without pausing. Do not treat silence, a tangent, or a
question as approval.

## Stage 2: Branch + Announce

1. **Branch discipline.** On the default branch (`main`/`master`/`trunk`)?
   Create a branch named from the plan's subject slug before any edit. Never
   implement on the default branch.
2. **Announce.** Run `ListAgents`. For every other agent that could be
   working in this repo (another local session, a teammate agent, a cloud
   session), `SendMessage` a short announcement: this pipeline is
   implementing <plan subject> on <branch>, expects to touch <file list from
   the plan>, and will ask again before refactoring the whole branch. No
   other agents listed → skip silently, don't manufacture ceremony.
3. **Record state.** Append a `## Pipeline` section to the plan file and
   keep it current at every transition from here on:

   ```markdown
   ## Pipeline

   - [x] planned (this document)
   - [x] approved — <date>
   - [ ] implemented
   - [ ] barrier cleared
   - [ ] refactored (or: skipped on request)
   - [ ] reviewed (confidence: _)
   - [ ] done

   **Branch:** <branch>  **Base at start:** <sha>
   **Files touched by this pipeline:** <living list>
   **Agent roster:** <who was found, what they said, or "none found">
   ```

   This section is what makes `/rc-loop <plan path>` resumable in a fresh
   session — write it as if the session dies right after.

## Stage 3: Implement

Execute the plan's Implementation steps in order.

- **Own files only.** Commit in logical units scoped strictly to files this
  pipeline touches; update the plan's file list as it grows. Never sweep in
  foreign changes — anything dirty or committed that this pipeline didn't
  write belongs to another agent or to Ray.
- **Verify as you go.** Run the plan's Verification section. Failures in
  pipeline-written code get fixed now; pre-existing failures get flagged in
  the report, not fixed.
- **Absorb the branch moving.** At each boundary within this stage, re-check
  `git status` and `git log` against the recorded baseline. Foreign commits:
  rebase onto them. A conflict between foreign work and pipeline work: stop
  and escalate to Ray — merge decisions are his.
- **Keep the plan honest.** Direction changes, discovered constraints, and
  Ray's mid-flight follow-ups (he sends them; adapt) all get folded into the
  plan file as they happen.

## Stage 4: Coordination Barrier

rc-refactor and rc-adversarial-review consume the **whole branch diff** —
including any other agent's work. They are blocked until every other agent
on this branch has communicated it is done.

1. `ListAgents`. Message each candidate agent: is it working on branch
   <branch> in <repo>? If yes: reply DONE when its work is committed and
   stable, because a whole-branch refactor and adversarial review are about
   to run.
2. The barrier clears when **every** agent working on the branch has replied
   DONE (or said it isn't on this branch), **and** `git status` shows no
   uncommitted work this pipeline didn't write.
3. **Never proceed past a silent agent.** Re-check periodically; after ~10
   minutes without a reply, escalate to Ray with the roster and each agent's
   status. He decides whether to wait or waive.
4. A **cloud session** that plausibly touches this branch can receive but
   not reply — that's an immediate escalation, not a wait.
5. A counterpart **rc-loop pipeline** on the same branch (its reply or
   roster row says so) is a deadlock risk — two pipelines waiting on each
   other. Escalate to Ray instead of mutually waiting.
6. No other agents at all → the barrier is a no-op. Note "none found" in the
   roster and move on.

Log the roster and outcome in the `## Pipeline` section. Known blind spot,
state it rather than over-trusting an empty roster: ListAgents only sees
Claude agents. A Codex CLI session, another tool, or a human on the branch
is invisible until their changes appear in git — which is why the
git-status check in step 2 is part of the barrier, not decoration.

## Stage 5: Refactor

Skipped cleanly if Ray said `skip refactor` (mark it in the state section).
Otherwise invoke `Skill(rc-refactor)` and follow it under overrides 2 and 3:
present the candidate list (including "considered and left alone") for the
record, apply the surviving extractions immediately, sync docs, run
verification now. Behavior preservation rules, revert-on-failure, and the
never-modify-tests prohibition all apply exactly as that skill states.

## Stage 6: Review

Skipped cleanly if Ray said `skip review` (mark it in the state section; the
final report then carries no confidence score). Otherwise:

1. **Barrier re-check** — refactor and review are one critical section, but
   time has passed: re-run `ListAgents` and the git-status check. A new
   agent on the branch re-arms the full Stage 4 barrier.
2. Invoke `Skill(rc-adversarial-review)`, passing `skip codex` through if
   Ray gave it. The skill runs as written: both tracks, verification of
   every finding, the fix loop until confidence ≥ 9 or a cap applies, and
   its own review plan saved to `~/.claude/plans/`.

## Stage 7: Stop and Report

The pipeline ends here. No PR — that's a separate `/rc-pr-open` ask from
Ray. Mark the `## Pipeline` section done (with the confidence score), then
report:

```
## Loop Complete: <plan subject>

**Confidence:** <X>/10 <one line: what the deduction is for, or what capped
it> <or: "no score — review skipped on request">
**Branch:** <branch> — <N> commits
**Plans:** <work plan path> · <review plan path>

### Shipped
- <commit-level summary of what was built>

### Refactor
- <what was consolidated, or "skipped on request" / "no candidates">

### Coordination
- <agent roster and how the barrier resolved, or "no other agents">

### Unresolved
- <unfixed findings, open questions, pre-existing failures flagged — or "nothing">
```

If any stage stopped short — review capped below 9, a barrier escalation
Ray hasn't answered, a conflict awaiting his call — the report says exactly
where the pipeline stands and what unblocks it. Never present a partial run
as complete.
