---
name: rc-loop
description: Full dev pipeline in one command — rc-plan (with batched scope interrogation) → Ray approves the plan → implement → rc-refactor → rc-adversarial-review to confidence 9+ → stop and report. Plan approval is the single human gate; after it, stages flow without pausing. Coordinates multiple sessions on one branch autonomously — file claims with deterministic tiebreaks, session heartbeats with automatic stale-breaking, and an exclusive branch lock gating the whole-branch refactor/review stages; no human sequencing. Any stage can be skipped by name — "skip refactor", "skip review", "skip codex" (passed into review) — and an existing plan path resumes mid-pipeline. Use when Ray asks to run the loop, the full pipeline, or plan-build-review a task end to end. Not the built-in /loop interval runner.
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

## Coordination Protocol

Cross-session coordination is fully autonomous — locks and heartbeats
decide, not Ray. The mechanics live in
`~/.claude/skills/rc-loop/rc-coord.sh` (run via Bash); state sits outside
the repo in `~/.claude/rc-loop/locks/<repo>/<branch>/`, shared by every
session on this machine — worktrees of the same repo included — so the
branch itself stays clean of coordination artifacts.

- **Session id.** Generate once at preflight — `rcloop-$(date +%s)-$$` —
  and record it in the `## Pipeline` section. Every script call takes it.
- **Claims.** `claim <sid> <files...>` registers the files this pipeline
  will write. Claim BEFORE editing, and extend the claim whenever the list
  grows. Exit 3 means contested, and the output names the winner.
- **Deterministic tiebreak.** Earlier claim timestamp wins; ties break
  lexicographically by session id — both sides compute the same answer, so
  nobody asks Ray to referee. The winner proceeds. The loser sequences
  itself: reorder plan steps to do uncontested work first, re-run
  `overlaps <sid>` between steps, touch contested paths only after the
  winner's claim is gone.
- **Heartbeat.** `hb-start <sid>` once, right after the first claim. It
  beats in the background and dies with this Claude session, so a crash
  goes stale (3 minutes) instead of wedging the branch; peers break stale
  claims and locks automatically (`break-stale` runs inside every wait).
- **Branch lock.** The whole-branch stages (refactor, review) run only
  while holding `lock-branch <sid>` — exclusive, atomically acquired,
  stale-breakable. `wait-branch-free <sid> <timeout>` before implementing:
  writing during another pipeline's critical section races its
  consolidation.
- **Waiting.** `wait-implement` and `wait-branch-free` poll internally and
  exit 0 (clear) or 3 (still waiting) at the timeout. For long waits run
  them as background Bash with a generous timeout (3600) — completion
  re-invokes you; on exit 3, re-run. A live heartbeat on the other side
  means waiting is correct, not stuck.
- **Limits, stated plainly.** Locks are cooperative: they cover rc-loop
  sessions. A non-rc-loop Claude session is reachable by SendMessage but
  holds no claim; a Codex session or a human is invisible until their
  changes appear in git. The git checks in Stages 3–4 exist for exactly
  those writers.

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
     building on it, then re-claim and restart the heartbeat under a fresh
     session id — the dead session's claim breaks as stale on its own.
   - **A prompt** — fresh run, start at Stage 1.
   - **Nothing** — ask Ray what to build before touching anything.
2. Confirm this is a git repo. Without git there is no diff base for
   refactor or review — say so and stop rather than improvising.
3. Record the current branch and `git log -1 --oneline` — the baseline for
   spotting other agents' work later.
4. Generate the coordination session id (`rcloop-$(date +%s)-$$`) per the
   Coordination Protocol.

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

1. **Branch discipline.** Already on a feature branch? Stay on it — that is
   the normal case, especially when sharing the branch with other agents.
   Branching happens in exactly one situation: the session is on the default
   branch (`main`/`master`/`trunk`), in which case create a branch named
   from the plan's subject slug before any edit. Never implement on the
   default branch, and never branch away from a branch Ray already chose.
2. **Claim + heartbeat.** Per the Coordination Protocol:
   - `claim <sid> <every file the plan expects to touch>`, then
     `hb-start <sid>`.
   - `wait-branch-free <sid> 3600` before the first edit — another pipeline
     may be mid-refactor/review on this branch.
   - Contested files (claim exited 3) → the tiebreak sequences the sessions
     autonomously: winner proceeds, loser works around the contested paths
     until the winner releases. No escalation.
3. **Nudge non-protocol sessions.** Run `ListAgents`. Any other Claude
   session that could be in this repo gets one SendMessage: this pipeline
   is implementing <plan subject> on <branch>, touching <files>; if that
   session works here too, it should run its work through rc-loop so the
   locks see it — or reply with the files it is touching. A reply becomes a
   shadow entry in the roster: avoid its stated files until that session
   says it's done (nudge again at the barrier). No reply → note it and rely
   on the git checks. No other agents listed → skip silently, don't
   manufacture ceremony.
4. **Record state.** Append a `## Pipeline` section to the plan file and
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
   **Session id:** <sid>
   **Files touched by this pipeline:** <living list>
   **Agent roster:** <live claims + shadow entries + lock log, or "none found">
   ```

   This section is what makes `/rc-loop <plan path>` resumable in a fresh
   session — write it as if the session dies right after.

## Stage 3: Implement

Execute the plan's Implementation steps in order.

- **Own files only, claims first.** Commit in logical units scoped strictly
  to files this pipeline touches; update the plan's file list as it grows.
  A file not yet claimed gets claimed before it is edited (exit 3 → the
  tiebreak; defer the path if lost). Never sweep in foreign changes —
  anything dirty or committed that this pipeline didn't write belongs to
  another agent or to Ray.
- **Verify as you go.** Run the plan's Verification section. Failures in
  pipeline-written code get fixed now; pre-existing failures get flagged in
  the report, not fixed.
- **Absorb the branch moving.** At each boundary within this stage: `git
  fetch` (when the branch has an upstream), then re-check `git status` and
  `git log` against the recorded baseline, including whether the remote is
  ahead (`git rev-list --count HEAD..@{upstream}`) — an agent on another
  machine shows up only this way. Foreign commits, local or fetched: rebase
  onto them. A conflict between foreign work and pipeline work: stop and
  escalate to Ray — merge decisions are his, the one thing locks don't
  arbitrate. Also run `break-stale` and confirm the branch lock is still
  free; if another pipeline somehow holds it, pause writes
  (`wait-branch-free`) until it releases.
- **Keep the plan honest.** Direction changes, discovered constraints, and
  Ray's mid-flight follow-ups (he sends them; adapt) all get folded into the
  plan file as they happen.

## Stage 4: Coordination Barrier — Automated

rc-refactor and rc-adversarial-review consume the **whole branch diff** —
including any other agent's work — so they run only inside the branch lock.
The barrier resolves itself through the Coordination Protocol; Ray is never
asked to sequence agents.

1. **Leave implement.** Commit any remaining pipeline work, then
   `stage <sid> barrier` — a claim at `barrier` is a promise of no more
   writes, and it is what peers' `wait-implement` watches for.
2. **Wait for peers.** `wait-implement <sid> 3600` (background Bash for
   long waits). A live heartbeat on a peer means it is still working — keep
   waiting, that's correct. A dead heartbeat means its claim gets broken
   automatically and logged. Exit 3 → re-run.
3. **Confirm git agrees.** No foreign uncommitted work in the tree, and
   after `git fetch`, not behind the upstream (no upstream → note it as
   moot). This is the only coverage for lock-invisible writers — non-rc-loop
   sessions, Codex, humans. Foreign dirt appearing here: nudge the roster's
   shadow entries once more and wait for it to be committed or claimed.
   Escalate to Ray only when it keeps changing with no owner claiming it —
   an unattributable writer is the one thing the protocol can't arbitrate.
4. **Take the branch lock.** `lock-branch <sid>`. Exit 3 means another
   pipeline won the race: `wait-branch-free <sid> 3600`, then re-take. Its
   refactor/review consumed this pipeline's committed work — run these
   stages anyway on the post-refactor branch. Two pipelines cannot deadlock
   here: acquisition is atomic and staleness breaks a dead holder.
5. **Log it.** Waits, broken locks, race outcomes, shadow-entry nudges —
   into the `## Pipeline` section.

No other live claims, no shadow entries, git clean → the barrier costs one
script call and a fetch. Don't manufacture ceremony around it.

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

1. **Critical-section check** — the branch lock from Stage 4 is still held;
   confirm it with `status`, run `break-stale`, and repeat Stage 4 step 3's
   git checks. New implement claims appearing now wait on the branch lock,
   not the reverse; foreign *git* changes with no owner re-arm Stage 4
   step 3.
2. Invoke `Skill(rc-adversarial-review)`, passing `skip codex` through if
   Ray gave it. The skill runs as written: both tracks, verification of
   every finding, the fix loop until confidence ≥ 9 or a cap applies, and
   its own review plan saved to `~/.claude/plans/`.

## Stage 7: Stop and Report

The pipeline ends here. No PR — that's a separate `/rc-pr-open` ask from
Ray. Release coordination state first — `unlock-branch <sid>` then
`release <sid>` — a finished pipeline still holding locks stalls every
peer. Then mark the `## Pipeline` section done (with the confidence score)
and report:

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
- <claims contested and how the tiebreak fell, barrier waits, locks broken,
  shadow entries — or "no other agents">

### Unresolved
- <unfixed findings, open questions, pre-existing failures flagged — or "nothing">
```

If any stage stopped short — review capped below 9, a barrier escalation
Ray hasn't answered, a conflict awaiting his call — the report says exactly
where the pipeline stands and what unblocks it. Never present a partial run
as complete.
