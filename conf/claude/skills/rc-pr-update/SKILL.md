---
name: rc-pr-update
description: Update the current PR's title and description to accurately reflect the branch's actual changes against the base branch. Use when the PR's direction has shifted during development and the title/description are stale.
allowed-tools: Read, Glob, Grep, Bash, Agent
user-invocable: true
---

# PR Update

You are updating a pull request's title and description to match the actual changes on the branch. The PR was opened earlier in the session (or a prior one), and development may have shifted direction since then. Your job is to make the PR accurately describe what it's shipping — not what was originally planned.

**You do NOT commit, push, or modify any code.** You only update the PR metadata via `gh pr edit`.

## Step 1: Gather Context

Run these in parallel:

1. **Detect the current branch and its PR**:
   ```bash
   git branch --show-current
   gh pr view --json number,title,body,baseRefName,url,state
   ```

2. **Detect the default branch**:
   ```bash
   git remote show origin | sed -n 's/.*HEAD branch: //p'
   ```

If there's no PR for the current branch, stop and tell the user. This skill only updates existing PRs.

If the PR is merged or closed, stop and tell the user.

## Step 2: Understand the Full Changeset

Run these to understand what the branch actually does:

1. **Commits on this branch**:
   ```bash
   git log --oneline <base>..HEAD
   ```

2. **Full diff against base**:
   ```bash
   git diff <base>...HEAD
   ```

3. **Files changed**:
   ```bash
   git diff --stat <base>...HEAD
   ```

Use the actual base branch from the PR metadata (`baseRefName`), not an assumption.

Read changed files where the diff alone doesn't tell the full story. Understand the intent, not just the mechanics.

## Step 3: Analyze and Categorize

From the diff and commits, determine:

- **Primary intent**: What is this PR fundamentally doing? (new feature, refactor, bugfix, infra change, etc.)
- **Key changes**: The 3-5 most important things this PR introduces or modifies.
- **Secondary effects**: Supporting changes that enable the primary intent (config changes, type updates, migrations, test additions).
- **What changed since the PR was opened**: Compare the current diff to the existing PR title/description. What shifted?

## Step 4: Draft the Updated PR

### Format Reference

Use the title and description format defined in `/rc-pr-write` (`~/.claude/skills/rc-pr-write/SKILL.md`). That skill is the single source of truth for PR formatting:

- **Title**: `<type>(<scope>): <description>` — conventional commits, scope required
- **Description**: Summary, Changes, Breaking changes (if any), Test plan

Read that file if you need the full spec. Apply it here.

### Additional rules for updates

- If the existing title still matches the format and accurately describes the current diff, keep it.
- Do NOT include stack tables (those are managed by `/rc-pr-stack`).
- Preserve any non-format content the user manually added to the description (e.g., reviewer notes, linked discussions) unless it's clearly stale.

## Step 5: Present for Review

Show the user the current and proposed title/description side by side:

```
## Current PR

**Title**: <current title>
**URL**: <pr url>

<current body, or "(empty)" if none>

---

## Proposed Update

**Title**: <proposed title>

<proposed body>
```

Then ask: **"Update the PR with this?"**

Wait for confirmation. Do not update until the user approves.

## Step 6: Apply

After user approval:

```bash
gh pr edit <number> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Verify the update succeeded by fetching the PR again:

```bash
gh pr view <number> --json title,url
```

Report the updated PR URL.

## Edge Cases

- **No changes on branch**: If `git diff <base>...HEAD` is empty, the branch has no changes. Tell the user.
- **Unpushed commits**: If the local branch is ahead of the remote, note this — the PR on GitHub won't reflect unpushed work yet. Suggest pushing first, or note that the description will describe changes not yet visible on the PR's diff.
- **Multiple concerns**: If the branch does genuinely unrelated things, flag this. Suggest splitting if appropriate, but still write the best description you can for the PR as-is.
