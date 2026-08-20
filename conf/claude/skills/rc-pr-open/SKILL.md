---
name: rc-pr-open
description: Create a new PR with a conventional-commit title and a diff-grounded reviewer narrative. Analyzes the full branch diff, drafts evidence-led metadata, presents it for approval, then creates the PR.
allowed-tools: Read, Glob, Grep, Bash, Agent
user-invocable: true
---

# PR Write

Create a new pull request with a standardized title and description.

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
- **Subpackage resolution**: When a monorepo has top-level directories containing subpackages (e.g., `apps/web`, `apps/server`, `apps/mobile`), resolve the scope to the subpackage where the majority of changes live. Don't stop at the top-level directory — a PR touching mostly `apps/web/` should be scoped to `web`, not `apps`.

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

## PR Description Style

A PR body is a reviewer narrative, not a form and not a changelog. Derive it from the full diff against the base branch. The reader should understand the central change, what it buys, how the implementation hangs together, and which behaviors or contracts may move.

### Default shape

```markdown
## Summary

<One or two unheaded thesis sentences. For a replacement or refactor, name both the old mechanism and the new one.>

- <Concrete system, user, correctness, or performance outcome>
- <Another outcome>

## Changes

- <Concept or subsystem> — <mechanism, important detail, and consequence>
- <Concept or subsystem> — <mechanism, important detail, and consequence>

## Breaking Changes

<If there are breaking changes, distinguish API compatibility from observable behavior and describe each affected behavior or consumer. If there are none, write exactly `N/A`.>
```

Adapt the shape to the change:

- The opening thesis is required. Do not put it under a generic `Summary` heading.
- Use an outcome list when the change has several distinct benefits. Lead with what improves, then explain why.
- Usually include `### Changes` for a substantial PR. Group bullets by architecture or behavior, not by file or commit.
- Always include `### Breaking changes`. Treat API, data, serialization, DOM, workflow, and other observable compatibility changes as breaking changes; "no API changes" does not mean "no breaking changes." If there are none, put exactly `N/A` under the heading.
- Omit other empty sections. Do not add `None` or boilerplate checklists.

### Diff-to-description pass

Before drafting, build a private claim-to-evidence map. Do not show it unless the user asks.

1. **Find the before/after thesis.** Locate the removed or bypassed mechanism and the replacement path. A new module alone does not prove that the system now uses it; trace its callers and integration points.
2. **Extract outcomes.** Read implementation, behavior tests, docs, schemas, generated output, and configuration. Translate mechanics into reviewer-relevant correctness, UX, operability, or performance effects.
3. **Group by concept.** Collapse related hunks into a few coherent systems such as parsing, caching, persistence, request flow, or editor behavior. Do not mirror the file tree.
4. **Scan compatibility surfaces.** Look for changed APIs, stored bytes, data shape, rendering/DOM, defaults, keyboard or workflow behavior, migrations, and removed fallback paths.
5. **Ground every claim.** Each material sentence must map to a diff hunk, test, generated artifact, or explicit user-provided context. Commits can explain intent, but they do not override the final diff.
6. **Check coverage and proportion.** Include every material reviewer-visible change, omit mechanical churn, and spend the most prose on the highest-impact or least-obvious parts of the diff.

If a motivation, benchmark, or risk claim is not supported by the branch or user context, ask the user, qualify it, or omit it. Never invent performance numbers, incidents, customer impact, or test results.

### Voice and sentence construction

- Write direct, compressed technical prose. Prefer "This replaces X with Y" over "This PR refactors X."
- Use causal structure: **mechanism → consequence**. Explain why a detail matters instead of merely naming it.
- Start bullets with an outcome or a strong concept label. A useful pattern is `<concept> — <implementation>, so <result>`.
- Use exact terms from the code and concrete examples in backticks when they clarify changed behavior.
- Contrast old and new behavior explicitly when that helps review.
- Calibrate risk language: use `may`, `expect`, or a scoped warning when impact depends on existing input or downstream assumptions.
- Be specific without narrating every hunk. Avoid marketing language, generic praise, filler, and changelog-style per-commit summaries.
- Do not hard-wrap the body. GitHub renders Markdown and wraps it for the reader.

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

Do not draft from truncated diff output. For a large changeset, save the complete diff to a temporary file and inspect it in chunks or per path. Read changed files where the patch lacks surrounding context. Read tests and docs as behavioral evidence, not as an afterthought. Understand the final system and its intent, not just the mechanics.

## Step 3: Analyze

Determine:

- **Type**: Is this a feat, fix, refactor, chore, docs, or test?
- **Scope**: What system area does this touch? If monorepo, identify the package.
- **Before/after thesis**: What mechanism or behavior existed before, and what replaces or changes it?
- **Outcomes**: What does the new behavior buy in correctness, UX, performance, maintenance, or operations?
- **Implementation concepts**: Which coherent subsystems explain the change better than a file list?
- **Compatibility**: What API, data, serialization, rendering, default, or workflow behavior changes?
- **Risk and evidence**: What's non-obvious, what could go wrong, and which hunks or tests support each claim?

Build the private claim-to-evidence map described above before drafting. If the diff cannot establish the motivation or intended compatibility contract, ask the user instead of guessing.

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
- **Multiple concerns**: Flag it. Suggest splitting if appropriate, but draft the best single PR you can.
- **Scope ambiguity**: If you can't determine a clear scope, ask the user rather than guessing.
