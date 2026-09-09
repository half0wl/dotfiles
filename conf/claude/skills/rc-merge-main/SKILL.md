---
name: rc-merge-main
description: Merge the repo's default branch (main/master) into the current branch and resolve conflicts, keeping the current branch's changes by default. Investigates both sides of every conflict, never uses blanket ours-strategies, and asks about risky conflicts in one batch before completing the merge.
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
user-invocable: true
---

# Merge Main

Merge the default branch into the current branch. Resolution policy: **this
branch's changes win** — but never blindly. Understand every conflict before
resolving it, and ask about the risky ones.

**Hard rules:**

- Never use `git merge -X ours`, `git merge -s ours`, or a blanket
  `git checkout --ours .`. Those discard incoming changes nobody looked at.
  Resolve each conflicted file by reading it.
- Never push. The merge commit is the only commit this skill creates.
- Never resolve a conflict you don't understand — that's what the ask step
  is for.
- The merge stays uncommitted until verification passes (Step 2 uses
  `--no-commit` for exactly this reason), so `git merge --abort` restores
  the branch exactly as it was at any point before Step 6. If the merge
  goes sideways, prefer aborting and asking over a half-understood
  resolution.

## Step 1: Preflight

Run in parallel:

1. **Current branch**:

   ```bash
   git branch --show-current
   ```

   Empty output means detached HEAD — stop and tell the user.

2. **Detect the default branch**:

   ```bash
   git remote show origin | sed -n 's/.*HEAD branch: //p'
   ```

   If there's no remote, fall back to whichever of `main`/`master` exists
   locally (`git rev-parse -q --verify <name>`).

3. **Working tree state**:

   ```bash
   git status --porcelain --untracked-files=no
   ```

   Untracked files don't block a merge, so don't gate on them — and if the
   merge would overwrite one, git refuses on its own with a clear error;
   surface that error and ask.

4. **Merge already in progress**:

   ```bash
   git rev-parse -q --verify MERGE_HEAD
   ```

5. **PR base** (stacked-branch guard):

   ```bash
   gh pr view --json baseRefName --jq .baseRefName 2>/dev/null
   ```

Then gate:

- **On the default branch** → stop. Nothing to merge into.
- **Dirty working tree** (tracked changes) → stop and ask: commit or stash
  first? Never auto-stash — popping a stash after a merge can conflict a
  second time.
- **Merge in progress** → stop and ask: continue resolving it or abort?
- **PR base isn't the default branch** (stacked PR, develop-based flow) →
  stop and ask. Merging the default branch into a stacked branch drags
  unrelated commits into the PR diff and wrecks the stack. Name the actual
  base and confirm the target before proceeding.

Then fetch and confirm the target exists:

```bash
git fetch origin
git rev-parse -q --verify origin/<default>
```

The merge target is `origin/<default>` (a stale local `main` is the classic
way to merge and still be behind). With no remote, target the local branch.

Two clone shapes need repair first:

- **Single-branch clone** — `origin/<default>` missing after the fetch.
  Fetch it explicitly:

  ```bash
  git fetch origin +refs/heads/<default>:refs/remotes/origin/<default>
  ```

- **Shallow clone** — `git rev-parse --is-shallow-repository` prints
  `true`. There's no merge base inside a shallow boundary, so the merge
  fails with "refusing to merge unrelated histories". Run
  `git fetch --unshallow origin` first (tell the user; it can be a big
  download).

## Step 2: Merge

```bash
git -c rerere.enabled=false merge --no-commit --no-edit origin/<default>
```

Both flags are load-bearing:

- `rerere.enabled=false` — rerere silently replays recorded resolutions
  from past merges, staging files with zero conflict markers so they never
  show up as conflicts to review. Those recordings can predate the incoming
  changes; nobody in this session reviewed them. Disable it for this merge.
- `--no-commit` — the merge stops before committing even when clean, so
  verification (Step 5) runs first and `git merge --abort` stays a valid
  escape hatch on every path.

Four outcomes:

- **"Already up to date"** → report that and stop.
- **Fast-forward** (HEAD moved, no `MERGE_HEAD` — `--no-commit` cannot stop
  an ff): the branch had no unique commits, so the pointer simply advanced.
  Report the fast-forward and stop — there is no merge commit to make.
- **Clean merge, stopped pre-commit** (`MERGE_HEAD` exists, no unmerged
  files) → skip to Step 5.
- **Conflicts** → list them and continue:

  ```bash
  git diff --name-only --diff-filter=U
  git status --porcelain
  ```

  The porcelain codes matter: `UU` both modified, `DU`/`UD` delete vs
  modify, `AA` both added, `DD` both deleted.

## Step 3: Resolve Each Conflict

For every conflicted file, understand both sides before touching it:

- Read the conflicted file. `HEAD` markers are ours; the other side is
  incoming from the default branch.
- What each side was doing:

  ```bash
  git log --merge --oneline -- <file>          # commits from both sides touching this file
  git diff $(git merge-base HEAD MERGE_HEAD) HEAD -- <file>        # our change
  git diff $(git merge-base HEAD MERGE_HEAD) MERGE_HEAD -- <file>  # their change
  ```

- If the markers alone are ambiguous, re-materialize with base context:
  `git checkout --conflict=diff3 -- <file>` (note: this discards any partial
  edits to that file).

Resolution policy, per conflicted hunk:

1. **Ours vs incoming churn** (formatting, renames, comment edits, a
   refactor our change supersedes) → keep ours.
2. **Both sides additive and independent** (both appended imports, list
   entries, enum cases, routes) → combine both. "Keep our changes" means
   ours survive, not that independent incoming additions get deleted.
3. **Incoming is functional and overlaps our change** → if our version
   already covers what theirs does, keep ours. If theirs folds in around
   ours trivially, combine. Anything less clean goes in the ask batch.
4. **Special files**:
   - **Lockfiles** (`bun.lock`, `pnpm-lock.yaml`, `package-lock.json`,
     `Cargo.lock`, ...) — never hand-merge. Resolve the manifest first
     (same policy as any file), then regenerate the lockfile with the
     repo's package manager. Tool unclear or regeneration fails → ask.
   - **Generated files** — resolve the source, regenerate the output. Can't
     regenerate → ask.
   - **Binary files** → ask.

**Always ask** (never self-resolve) when:

- The incoming side fixes a bug or security issue in lines our change also
  touches — keeping ours could reintroduce the bug.
- Keeping ours would delete functionality the default branch added, not
  just override how it works.
- Both sides rewrote the same logic with incompatible intent.
- Delete-vs-modify in either direction (`DU`/`UD`).
- Migrations, schemas, or config with runtime consequences.
- You can't confidently state what both sides intended.

## Step 4: Ask (Batched)

Collect every uncertain conflict into **one** message — never ask one at a
time. For each:

```
### <file>

- **Ours**: <what our change does>
- **Theirs**: <what the incoming change does>
- **If we keep ours**: <what gets discarded and why that might matter>
- **Recommendation**: keep ours / take theirs / combine — <one line why>
```

Wait for answers, then apply them. The in-progress merge is stable — it's
fine to sit in the conflicted state while waiting.

## Step 5: Verify

1. If conflicts were resolved, stage the resolutions (`git add <files>`),
   then check nothing was missed:

   ```bash
   git diff --name-only --diff-filter=U                     # must be empty
   git diff --cached --check | grep 'leftover conflict marker'   # must be empty
   ```

   Don't act on `--check`'s other output: during a merge it scans every
   incoming change, so whitespace complaints about files main touched are
   expected — not a merge error, and not yours to fix.

2. Run the repo's cheap checks if they exist — typecheck/build/lint from
   `package.json` scripts, `cargo check`, `go build ./...`. Skip long test
   suites unless the user asks.
3. If a check fails, determine whether the merge broke it or it was already
   failing on our branch before the merge. Report either way — never claim
   a clean merge without having verified it. The merge is still uncommitted
   at this point, so `git merge --abort` remains a clean exit if the user
   wants out.

## Step 6: Commit and Report

Complete the merge without opening an editor (git already prepared the
merge message, including the conflicted-file list):

```bash
git commit --no-edit
```

This is the commit for both the clean and conflicted paths; the
fast-forward path already stopped in Step 2. Do not push. Then report:

```
## Merged <default> into <branch>

- <N> commits brought in (<oldest>..<newest>)
- Conflicts: <N> files
  - `<file>` — kept ours: <one line>
  - `<file>` — combined: <one line>
  - `<file>` — took theirs (per your call): <one line>
- Verification: <what ran and the result>
- Not pushed — push when ready.
```

## Edge Cases

- **Default branch isn't main/master** (e.g. `develop` as origin HEAD):
  trust the detection, merge that.
- **Unpushed local commits on local `main`**: irrelevant — we merge
  `origin/<default>`, and never touch the local default branch.
- **Submodule conflicts**: don't guess a pointer. Ask which commit the
  submodule should be at.
- **Massive conflict count** (a stale branch hitting a big refactor): pause
  after listing the files and confirm merge is still the right move before
  resolving — a rebase or fresh branch may serve better. Flag it, let the
  user decide.
