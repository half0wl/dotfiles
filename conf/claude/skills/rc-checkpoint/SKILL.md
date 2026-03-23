---
name: rc-checkpoint
description: Checkpoint the current session by updating project documentation (TASKS.md, CLAUDE.md, ARCHITECTURE.md, etc.) with learnings, decisions, and progress. Does NOT commit — just surfaces changes for review.
allowed-tools: Read, Glob, Grep, Bash, Edit, Write, Agent
user-invocable: true
---

# Session Checkpoint

You are checkpointing the current session. Your job is to capture what was learned, decided, changed, or discovered during this session and persist it into project documentation so future sessions (or other engineers) benefit.

**Do NOT commit anything.** Just make the edits. The user will review and commit when ready.

## Step 1: Assess What Happened This Session

Review the conversation history to identify:

1. **Decisions made** — architectural choices, trade-offs, rejected alternatives
2. **New understanding** — things learned about the codebase, dependencies, or domain that weren't obvious before
3. **Work completed** — features added, bugs fixed, refactors done
4. **Work in progress** — things started but not finished, next steps identified
5. **Problems discovered** — bugs found, tech debt identified, risks surfaced
6. **Pattern changes** — new conventions established, old patterns deprecated

Be thorough. Scan the full conversation, not just the last few messages.

## Step 2: Identify Target Files

Check which documentation files exist in the project:

```bash
# Check for documentation files at project root and key directories
ls -la TASKS.md CLAUDE.md ARCHITECTURE.md TODO.md CHANGELOG.md DECISIONS.md 2>/dev/null
```

Also check for:
- `CLAUDE.md` files in subdirectories (these contain package-specific instructions)
- Any `*.md` files that serve as living documentation

**Rules for which files to update:**

| File | What goes here |
|------|---------------|
| `CLAUDE.md` (root) | Development guidelines, conventions, architecture rules, environment setup — things that shape how an agent works in this repo |
| `CLAUDE.md` (subdirectory) | Package-specific instructions, constraints, gotchas |
| `ARCHITECTURE.md` | System design, component relationships, data flow, design decisions |
| `TASKS.md` / `TODO.md` | Work items: completed (checked off), in-progress, discovered |
| Memory files (`~/.claude/projects/*/memory/`) | Cross-session context: user preferences, project state, external references |

## Step 3: Draft Updates

For each file you're updating:

1. **Read the current file first.** Understand existing structure and voice.
2. **Integrate, don't append.** New information should be woven into the right section, not dumped at the bottom.
3. **Match the existing style.** If the file uses bullet points, use bullet points. If it uses headers, use headers.
4. **Be specific.** "Updated sync logic" is useless. "Added QRESYNC support to folder_sync.rs with fallback to CONDSTORE when server doesn't advertise QRESYNC" is useful.
5. **Remove stale content.** If something documented is no longer true, update or remove it. Stale docs are worse than no docs.
6. **Mark completed work.** If TASKS.md has items that were finished this session, check them off with `[x]`.

## Step 4: Create Missing Files If Warranted

Only create a new documentation file if:
- The project clearly needs it (e.g., there's no TASKS.md and there are tracked work items)
- The content doesn't fit naturally in an existing file
- The user's project conventions suggest it

Do NOT create files just to have them. Empty or near-empty docs are noise.

## Step 5: Update Memory (If Applicable)

Check if any session learnings should be persisted to Claude's memory system:
- Project decisions or context that will matter in future sessions
- New understanding of the user's preferences or workflow
- External references discovered (Linear tickets, dashboards, docs)

Use the memory system's existing conventions (check `~/.claude/projects/*/memory/MEMORY.md`).

## Step 6: Present Summary

After making all edits, present a brief summary:

```
## Checkpoint Summary

### Files Updated
- `CLAUDE.md` — added X, updated Y
- `TASKS.md` — checked off A, added B

### Files Created
- (none, or list)

### Key Learnings Captured
- (1-3 bullet points of the most important things persisted)

### Not Captured (and why)
- (anything you intentionally skipped, e.g., "debug session details — ephemeral, not worth documenting")
```

## Important

- **Bias toward updating over creating.** Fewer, richer files beat many thin ones.
- **Don't document the obvious.** If it's in the code, in git history, or derivable from reading the project, skip it.
- **Capture the WHY.** Code shows what. Docs should show why. "We chose X because Y, not Z because W."
- **Be honest about gaps.** If work is incomplete, say so. Don't paper over it.
- **No commits.** The user reviews the diff and decides what ships.
