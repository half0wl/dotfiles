---
name: rc-refactor
description: Consolidation refactor of the current branch's diff against main. Finds repeated literals, magic numbers, duplicated logic, inline type shapes, and copy-pasted config across the branch's changed files, then extracts them into named constants, pure helpers, and shared types. Presents the full candidate list for approval before touching anything; preserves behavior exactly. Finishes by syncing the project's CLAUDE.md and ARCHITECTURE.md to the refactored code — source code is the truth. Use when Ray asks to refactor for consolidation, dedupe the branch, extract constants/helpers, or clean up duplication before review.
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, ListAgents, SendMessage
---

# Consolidation Refactor

Review the current branch's diff against main and refactor for
consolidation. This is a pure refactor: behavior is preserved exactly — no
logic changes, no renames beyond the extractions themselves.

**Regressions are unacceptable.** A consolidation that changes behavior is
a failure of the whole exercise, no matter how clean the result reads. When
a candidate can't be extracted with provable behavior preservation, leave
it and say why — a skipped extraction costs nothing; a regression costs
trust.

## Step 0: Preflight

1. Confirm you're on a branch, not main itself. On main with nothing to
   diff against, stop and say so.
2. Resolve the base: `main` by default; if the repo's default branch is
   named differently (`master`, `trunk`), use that and note it.
3. Get the file list: `git diff main...HEAD --name-only`. Empty list →
   stop, nothing to do.
4. Note the state of the working tree. Uncommitted changes are fine —
   they may be another agent's work in progress — but the refactor
   commits must contain only extraction work; never sweep them in.

## Scope

Only files changed on this branch. Do not touch files outside the diff
unless extracting a shared constant/helper requires creating a new file or
adding to an existing shared module.

## Concurrent Agents

Other agents may be working on this branch at the same time. Assume the
tree can shift between any two steps; coordinate instead of colliding.

- At preflight, check ListAgents for other active sessions. If any look
  like they're on this repo, message them (SendMessage) with the files you
  plan to touch and ask what they have in flight. Hold off on contested
  files until you've heard back or Ray says to proceed.
- Stage surgically: `git add <specific files>` only — never `git add -A`,
  `git add .`, or `git commit -a`. Another agent's half-finished work must
  not ride along in an extraction commit.
- Re-read each file immediately before editing it. If it changed since
  candidate enumeration, re-verify the extraction still applies; if it no
  longer does, drop the candidate and note it — don't force it.
- If new commits land mid-refactor, re-run the diff and reassess. Never
  reset, amend, or force-push — that rewrites history another agent may
  be building on.
- On an edit conflict (file changed underneath you), reapply your change
  on top of their version. Never clobber their edit to make yours land.

## What to Look For

1. **Repeated string literals** (error messages, event names, keys, URLs,
   magic values) appearing 2+ times. Extract into named constants in the
   nearest sensible shared location. Use `as const` where appropriate.
2. **Repeated magic numbers** (timeouts, limits, retry counts). Same
   treatment, with a name that explains intent, not value.
3. **Duplicated logic blocks** (near-identical functions, copy-pasted
   conditionals, repeated type guards). Extract into a single pure
   function with proper types. No `any`.
4. **Repeated type shapes** defined inline in multiple places. Lift into a
   shared type/interface.
5. **Repeated config or option objects**. Extract into a single source of
   truth.

## Rules

- Interface-first: if extracting a function, define its signature and
  types before implementation.
- Do not extract things that appear only once, or twice with genuinely
  different semantics. Coincidental duplication is not duplication. When
  unsure, leave it and note it in the summary.
- Minimal abstractions: prefer a constant or flat helper over a class or
  nested module. No premature generalization.
- Preserve behavior exactly. This is a pure refactor — no logic changes,
  no renames beyond the extractions themselves. Watch the subtle ways an
  extraction changes semantics: evaluation order, shared vs. fresh object
  identity (a hoisted config object is mutated by one caller and seen by
  another), string near-duplicates that differ by one character, and
  widened or narrowed types at the new boundary.
- Keep changes reviewable: group related extractions into logical commits
  with clear messages.

## Process

1. **Enumerate candidates first.** Read the diff, then present the full
   list before changing anything — for each candidate: what it is, every
   location (`file:line`), occurrence count, and where the extraction
   would live. Include a "considered and left alone" section for
   borderline cases. **Wait for Ray's approval. Do not edit a single file
   before it arrives.** He may strike items from the list — refactor only
   what survives.
2. **Refactor.** Apply the approved extractions, grouped into logical
   commits with clear messages.
3. **Sync docs.** After the extractions land, check the project's
   `CLAUDE.md` and `ARCHITECTURE.md` (repo root and any affected package
   directories) for content the refactor invalidated — file paths, module
   names, constants or helpers described by their old location, patterns
   the docs narrate that the code no longer follows. Source code is the
   truth: update the docs to describe the code as it now is; never bend
   the refactor to match stale docs. Scope is strictly what this refactor
   invalidated — no drive-by rewrites, no fixing unrelated staleness
   (flag it in the summary instead). If a doc doesn't exist, skip it;
   don't create one. Commit doc updates as their own commit so the
   extraction commits stay pure.
4. **Verify — only when Ray says to.** Do not run typecheck or the test
   suite on your own; Ray triggers verification explicitly. After
   refactoring, report the work as **unverified** and name the commands
   you'd run (discover the project's own — package.json scripts,
   Makefile, justfile), then wait. Until verification passes, never call
   the refactor done or claim behavior is preserved — "extracted,
   unverified" is the strongest claim available. When Ray gives the word:
   both must pass on the refactored code. Fix any breakage you caused; do
   not fix pre-existing failures — flag them instead. If a failure's
   provenance is unclear, check whether it fails on the pre-refactor
   commit before claiming it's pre-existing. Never modify a test file to
   make it pass — not an assertion, not an expected value, not a skip or
   a snapshot update. A failing test after a pure refactor means the
   extraction wasn't behavior-preserving: revert that extraction. (Test
   files changed on the branch remain fair game for approved
   consolidation — the prohibition is on editing them in response to a
   failure.)
5. **Summarize:** what was extracted, where it lives now, what you
   deliberately left alone and why, which doc sections were synced (or
   "docs untouched — nothing referenced the changed code", plus any
   unrelated staleness spotted but left alone), and the verification
   status — either the results (exact commands and outcomes, including
   any pre-existing failures flagged) or a clear "unverified, awaiting
   go-ahead" with the commands ready to run.
