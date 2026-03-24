---
name: rc-pr-write
description: Create a new PR with standardized conventional-commit title and structured description. Analyzes the branch diff, drafts title/description, presents for approval, then creates the PR.
allowed-tools: Read, Glob, Grep, Bash, Agent
user-invocable: true
---

# PR Write

Create a new pull request with a standardized title and description. This skill is the single source of truth for PR formatting. Other skills (`rc-pr-update`, `rc-pr-stack`) reference this format.

**You do NOT commit or push code.** If unpushed commits exist, prompt the user to push first.

---

## PR Title Format

```
<type>(<scope>): <description>
```

### Type (required)

One of: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`

### Scope (required)

The system area this change touches.

- **Single-package repos**: use the domain area (e.g., `auth`, `billing`, `ingest`, `api`)
- **Monorepos**: use `package/area` where `package` is the package name and `area` is the domain within it. For example, in a monorepo with `packages/auth/session/...`, use `auth/session`. The package name acts as a namespace.

Pick the most specific scope that accurately covers the change. If the change genuinely spans multiple unrelated scopes, use `*` as the scope (e.g., `refactor(*): normalize error handling across services`). Don't comma-separate.

### Description

- Imperative mood, lowercase, no trailing period
- Under 50 characters (after the `type(scope): ` prefix)
- Total title under 72 characters
- Specific. "update auth" is bad. "expire stale session tokens on refresh" is good.

### Examples

```
feat(auth): add OIDC provider integration
fix(billing/invoices): correct proration for mid-cycle upgrades
refactor(ingest): extract pipeline stages into composable transforms
chore(ci): pin node version in GitHub Actions
docs(api): add rate limiting section to openapi spec
test(auth/session): cover token refresh edge cases
```

---

## PR Description Format

```markdown
## Summary

<2-5 sentences. What this PR does and why. Lead with the what, follow with the why. Be specific about the approach — not just "refactored X" but "replaced X with Y because Z.">

## Changes

<Bulleted list of key changes, grouped logically. Each bullet describes a meaningful behavior change, not a file-level diff. Focus on what's different for the system, not what lines moved.>

## Breaking changes

<What breaks, who is affected, and the migration path. If nothing breaks, omit this section entirely — do not include it with "None.">

## Test plan

<Bulleted checklist. Include both automated tests (what was added/updated) and manual verification steps where relevant.>


🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Description rules

- **No changelog-style per-commit breakdowns.** The reviewer has the commit list.
- **No obvious filler.** "This PR makes changes to the codebase" is noise.
- **Lead with intent.** Why does this change exist? What problem does it solve?
- **Be honest about risk.** If something is uncertain or fragile, say so in the summary or changes.

---

## Step 1: Gather Context

Run in parallel:

1. **Current branch and remote state**:
   ```bash
   git branch --show-current
   git log --oneline @{upstream}..HEAD 2>/dev/null  # unpushed commits
   ```

2. **Detect the default branch**:
   ```bash
   git remote show origin | sed -n 's/.*HEAD branch: //p'
   ```

3. **Check if a PR already exists**:
   ```bash
   gh pr view --json number,url 2>/dev/null
   ```

If a PR already exists, stop and tell the user to use `/rc-pr-update` instead.

If there are unpushed commits, tell the user and ask if they want to push first.

## Step 2: Understand the Changeset

Run these against the default branch:

1. **Commits on this branch**:
   ```bash
   git log --oneline <default>..HEAD
   ```

2. **Full diff**:
   ```bash
   git diff <default>...HEAD
   ```

3. **Files changed**:
   ```bash
   git diff --stat <default>...HEAD
   ```

Read changed files where the diff alone doesn't tell the full story. Understand the intent, not just the mechanics.

## Step 3: Analyze

Determine:

- **Type**: Is this a feat, fix, refactor, chore, docs, or test?
- **Scope**: What system area does this touch? If monorepo, identify the package.
- **Primary intent**: What problem does this solve?
- **Key changes**: The 3-5 most important behavioral changes.
- **Breaking changes**: Does this break any existing behavior, API, or contract?
- **Risk**: What's non-obvious or could go wrong?

## Step 4: Draft

Write the title and description following the format above.

Present to the user:

```
## Proposed PR

**Title**: <title>
**Base**: <default branch>

<description body>
```

Then ask: **"Create PR with this?"**

Wait for confirmation. Do not create until the user approves.

## Step 5: Create

After approval:

```bash
gh pr create --base <default> --title "<title>" --body "$(cat <<'EOF'
<body>
EOF
)"
```

Verify:

```bash
gh pr view --json number,title,url
```

Report the PR URL.

## Edge Cases

- **No changes on branch**: If `git diff <default>...HEAD` is empty, tell the user.
- **Unpushed commits**: Prompt to push before creating. GitHub can't see unpushed work.
- **PR already exists**: Direct to `/rc-pr-update`.
- **Multiple concerns**: Flag it. Suggest splitting if appropriate, but draft the best single PR you can.
- **Scope ambiguity**: If you can't determine a clear scope, ask the user rather than guessing.
