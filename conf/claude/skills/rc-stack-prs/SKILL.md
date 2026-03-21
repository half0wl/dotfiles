---
name: rc-stack-prs
description: Manage stacked PRs for large changes. Split work into chained PRs, create PRs with stack-aware descriptions, update branches after merges, and switch PR bases on GitHub. Use when the user wants to stack PRs, update a stack, view a stack, or create PRs for a stack. CRITICAL: Never commits or pushes to main/master.
allowed-tools: Read, Glob, Grep, Bash, Edit, Write
---

# Stacked PRs

Stacked PRs split a large change into a chain of dependent pull requests, each targeting the previous one as its base. This makes code review faster and more focused. This skill automates the entire lifecycle: creating the branch chain, opening PRs with correct bases and stack-aware descriptions, rebasing after merges, and updating PR bases on GitHub.

**Typical invocation context:** The user runs this skill while on the feature branch. On startup, record the current branch name as the **source branch** (`git branch --show-current`). Use this to read diffs and cherry-pick commits from, but never modify it. When creating stack branches, switch away from the source branch to `origin/<default>` first.

---

## SAFETY RULES

These two rules are **inviolable**. Check them before every mutating git operation.

### Rule 1: Never Commit or Push to Main/Master

Before EVERY `git commit`, `git push`, or `git rebase` that would land commits:

1. Run `git branch --show-current`
2. If the result is `main`, `master`, or empty (detached HEAD): **STOP. REFUSE. Alert the user.**

Also never:

- `git push --force` or `git push --force-with-lease` to main/master
- `git merge` into main/master locally
- Any operation that would modify the default branch

### Rule 2: Never Touch the Original Feature Branch

The user has an existing large branch with an open PR. This skill creates _new_ stacked branches that cherry-pick or split that work. The original branch and its PR must be left **completely untouched**:

- No commits to it
- No rebases of it
- No closing its PR
- No deleting it
- Never check it out to make changes

The stack is built independently: `default-branch -> 01 -> 02 -> ...`. The original branch stays open as-is.

---

## Branch Naming Convention

```
rc/<stack-name>/<NN>-<description>
```

- `<stack-name>`: kebab-case feature name (e.g., `oauth-migration`)
- `<NN>`: zero-padded two-digit number starting at `01`
- `<description>`: kebab-case slice description (e.g., `extract-interfaces`)

Examples:

```
rc/oauth-migration/01-extract-interfaces
rc/oauth-migration/02-implement-provider
rc/oauth-migration/03-add-migration
```

Discover existing branches in a stack:

```bash
git branch --list 'rc/<stack-name>/*' --sort=refname
```

---

## Detecting Default Branch

Always detect — never assume `main`:

```bash
git remote show origin | sed -n 's/.*HEAD branch: //p'
```

Store the result and reuse it throughout the operation.

---

## PR Title Convention

PR titles use a stack-aware prefix format:

```
[<feature>-<number>/<total>] <description>
```

- `<feature>`: short feature name (ask the user what to use if not obvious)
- `<number>`: this PR's position in the stack (1-indexed)
- `<total>`: total number of PRs in the stack
- `<description>`: concise description of this slice

Examples:

```
[oauth-3/5] add migration scripts
[oauth-1/5] extract auth interfaces
```

When creating PRs, **ask the user what feature prefix to use** for the title format before proceeding. Update the `<total>` in all PR titles whenever the stack size changes (e.g., when adding a new branch or after cleanup).

---

## Operations

### a. View Stack

1. Discover branches: `git branch --list 'rc/<stack-name>/*' --sort=refname`
2. For each branch, query: `gh pr list --head <branch> --json number,state,baseRefName,url,title`
3. Display a table:

```
Branch                                  | PR   | State  | Base                                   | URL
rc/oauth/01-extract-interfaces         | #123 | MERGED | main                                   | https://...
rc/oauth/02-implement-provider         | #124 | OPEN   | rc/oauth/01-extract-interfaces         | https://...
rc/oauth/03-add-migration              | #125 | OPEN   | rc/oauth/02-implement-provider         | https://...
```

4. Flag if any PR's base needs updating (e.g., a predecessor was merged and the next PR should now target `main`).

### b. Create New Stack

1. Record the current branch as the **source branch**: `git branch --show-current`. This is the feature branch to read/cherry-pick from. It will not be modified.
2. Detect the default branch.
3. Run `git fetch origin`.
4. **Check for ref conflicts**: Git cannot create `rc/<name>/01-desc` if a branch `rc/<name>` already exists (refs clash — a ref can't be both a leaf and a prefix). Before creating, check:
   ```bash
   git show-ref --verify --quiet refs/heads/rc/<stack-name>
   ```
   If it exists, ask the user to rename or delete it first (locally and on the remote):
   ```bash
   git branch -m rc/<stack-name> rc/<stack-name>-old   # rename local
   git push origin :rc/<stack-name> rc/<stack-name>-old  # rename remote
   ```
   Also check for remote-only refs: `git show-ref --verify --quiet refs/remotes/origin/rc/<stack-name>` — if a remote tracking ref exists, prune it with `git fetch --prune origin`.
5. From `origin/<default>` (NOT from the feature branch), create the first branch:
   ```bash
   git checkout -b rc/<stack-name>/01-<desc> origin/<default>
   ```
6. Cherry-pick or add the first slice of changes from the source branch. Use `git log <default>...<source-branch>` and `git diff <default>...<source-branch>` to understand the full changeset and plan slices.
7. The source (feature) branch is never checked out or modified.

### c. Add to Stack

1. Find the top branch in the stack:
   ```bash
   git branch --list 'rc/<stack-name>/*' --sort=-refname | head -1
   ```
2. Determine the next number (increment NN).
3. Create the next branch from the top:
   ```bash
   git checkout -b rc/<stack-name>/<next-NN>-<desc> rc/<stack-name>/<top-NN>-<desc>
   ```

### d. Create PRs

For each branch in the stack that doesn't yet have a PR:

1. **Safety check**: verify current branch is not main/master.
2. Push the branch:
   ```bash
   git push -u origin rc/<stack-name>/<NN>-<desc>
   ```
3. Determine the base:
   - First branch (`01`): base is the default branch
   - Subsequent branches: base is the previous branch in the stack
4. Create the PR using the **PR Title Convention** (`[<feature>-<number>/<total>] <description>`):
   ```bash
   gh pr create --base <base-branch> --title "[<feature>-<N>/<total>] <desc>" --body "<body with stack section>"
   ```
5. After all PRs are created, update each PR body with the full stack section (since PR numbers are now known).

### e. Update Stack After Merge

This is the most complex operation. Execute step by step:

1. `git fetch origin`
2. Detect which PRs are merged: `gh pr view <branch> --json state` for each branch.
3. Find the **merge boundary**: the last consecutively merged branch in the stack.
4. For the **first unmerged branch**:
   - Save old ref: `OLD_REF=$(git rev-parse origin/rc/<stack-name>/<last-merged>)`
   - Rebase onto default branch:
     ```bash
     git rebase --onto origin/<default> $OLD_REF rc/<stack-name>/<first-unmerged>
     ```
   - **Safety check** on current branch, then:
     ```bash
     git push --force-with-lease origin rc/<stack-name>/<first-unmerged>
     ```
   - Update PR base:
     ```bash
     gh pr edit <pr-number> --base <default>
     ```
5. For each **subsequent unmerged branch**:
   - Save old ref of its predecessor: `OLD_REF=$(git rev-parse <old-predecessor-ref>)`
   - The predecessor was just rebased, so use the old ref as the upstream:
     ```bash
     git rebase --onto rc/<stack-name>/<predecessor> $OLD_REF rc/<stack-name>/<current>
     ```
   - **Safety check**, then force-push with lease.
   - PR base stays as its predecessor (unchanged).
6. **Always refresh stack status on ALL PRs** (merged and open). For each PR in the stack, query its state and update its body with the current stack table. This includes merged PRs — their status column should show `✅ merged` and the stack table should reflect the current state of all other PRs. Also update PR titles if the total count has changed.
7. Optionally delete merged local and remote branches:
   ```bash
   git branch -d rc/<stack-name>/<merged-branch>
   git push origin --delete rc/<stack-name>/<merged-branch>
   ```

### f. Dry Run / Plan Mode

When the user asks to "plan" or "dry run" any stack operation, do **NOT** execute any mutations. Instead:

1. Analyze the diff or feature branch and propose how to split it into slices.
2. List each proposed branch name, its base, a title, and which commits/files would go in each slice.
3. Show the PR creation plan: titles, bases, body previews.
4. For update operations, show which rebases and base changes would happen.
5. **Wait for explicit user approval** before executing anything.

This applies to any operation — create, create-prs, update. If the user says "plan" or "dry run", show what would happen without doing it.

### g. Cleanup

After all PRs in the stack are merged:

1. `git fetch origin`
2. Verify all PRs show state `MERGED`.
3. Switch to the default branch: `git checkout <default> && git pull`
4. Delete local branches:
   ```bash
   git branch -d rc/<stack-name>/01-... rc/<stack-name>/02-... ...
   ```

---

## PR Body Template

Every PR in the stack gets an auto-generated stack section in its body:

```markdown
## Stack

| #   | PR       | Title                        | Status           |
| --- | -------- | ---------------------------- | ---------------- |
| 1   | #123     | extract interfaces           | ✅ merged        |
| 2   | **#124** | **implement oauth provider** | **👉 this PR**  |
| 3   | #125     | add migration                | ⏳ open          |
```

Status values:
- `✅ merged` — PR has been merged
- `**👉 this PR**` — the current PR (bold the entire row)
- `⏳ open` — PR is open, waiting for review or blocked on a predecessor

When creating or updating PRs, regenerate this section with current state for **all** PRs in the stack using `gh pr edit <number> --body`. Query each PR's actual merge state (`gh pr view <number> --json state`) to set the correct status emoji.

### h. Refresh Stack Status

When the user asks to "update status", "refresh stack", or "sync PR descriptions":

1. Discover all branches in the stack.
2. For each branch, query the PR state: `gh pr view <branch> --json number,state,title`
3. Regenerate the Stack table in every PR body with current statuses (✅/👉/⏳).
4. Update all PR bodies in parallel: `gh pr edit <number> --body "..."`

---

## Build Isolation

**Each PR in the stack must build/typecheck/lint independently.** When checking out files from the source branch with `git checkout <source> -- <file>`, the file gets the *final* state — which may reference code that only exists in later PRs.

Before committing each branch, verify that shared files only reference symbols, modules, or resources available at *that point* in the stack:

1. **Aggregation files** (barrel exports, index files, registries, route tables, DI containers, etc.): Only include entries whose implementations exist on the current branch. If the source branch's aggregation file references items introduced in later PRs, strip those entries. Add them back in the PR that introduces the dependency.

2. **Files that consume later-PR code** (imports, includes, configuration references): If a file was modified on the source branch to use something introduced in a later PR, keep that file at its default-branch state in earlier PRs. Move the change to the PR that introduces the dependency.

3. **Verification step**: After staging files for a branch, scan for forward-references — imports/requires/includes that point to files not yet on disk:
   ```bash
   # Check that all local references in changed files resolve to existing files
   git diff --cached --name-only | xargs grep -h "import\|require\|include" 2>/dev/null | # adapt pattern to project language
   ```
   If the project has a build/typecheck command, run it to confirm the branch compiles cleanly.

When splitting a feature branch, treat `git checkout <source> -- <file>` as a starting point, then **edit the file to remove forward-references** before committing.

---

## Error Handling

- **Rebase conflicts**: Stop immediately. Inform the user of the conflict. Show which files conflict and the branches involved. Do not attempt to auto-resolve.
- **Dirty working tree**: Refuse to start any operation. Tell the user to commit or stash changes first.
- **Out-of-order merges**: If a branch is merged before its predecessor, flag this as an error. The stack should be merged in order (01 first, then 02, etc.).
- **Detached HEAD**: Alert the user and refuse to continue. A branch must be checked out.
- **Push failures**: If `--force-with-lease` fails, someone else pushed. Alert the user to review before retrying.
- **Git ref conflicts** (`cannot lock ref ... exists; cannot create`): This happens when a branch like `rc/<name>` already exists and you try to create `rc/<name>/01-desc` — git refs can't be both a leaf and a directory prefix. Solutions: (1) choose a different stack name that doesn't collide (e.g., `rc/<name>-stack/01-desc`), or (2) rename/delete the conflicting branch first. Always check for this before creating the first branch in a stack.
