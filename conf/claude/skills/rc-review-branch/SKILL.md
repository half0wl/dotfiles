---
name: rc-review-branch
description: Comprehensive code review of the current branch's changes against the base branch. Reviews for correctness, security, architecture, performance, types, error handling, edge cases, and testing. Rates confidence 1-10 and fixes issues until 9+.
allowed-tools: Read, Glob, Grep, Bash, LSP, Edit, Write, Agent
---

# Branch Code Review

You are reviewing the current branch's changes. This is adversarial review — your job is to find what's wrong before it ships. Assume bugs exist until you've proven otherwise.

**You may not stop until your confidence reaches at least 9/10.** The 1-point deduction is reserved for things you genuinely cannot determine from static analysis (runtime behavior under load, production data edge cases, external service interactions). It is NOT for things you could have checked but didn't.

## Step 1: Understand the Change

Before reviewing anything, understand what you're looking at.

1. **Identify the base branch**: Run `git merge-base main HEAD` then `git log --oneline main..HEAD` to see all commits on this branch.
2. **Get the full diff**: Run `git diff main...HEAD` to see the complete change set.
3. **Read commit messages**: They tell you the intent. If they don't, that's a finding.
4. **Identify the scope**: Which files changed? What subsystems are affected?
5. **Read project standards**: Find and read `CLAUDE.md` and `ARCHITECTURE.md` files at the repo root and in any directories containing changed files. These define the project's coding standards, architectural decisions, and constraints. Every rule in these files is a review criterion.

Write a brief summary:

- **Intent**: What is this change trying to accomplish?
- **Scope**: What files/modules are touched?
- **Blast radius**: What could break if this is wrong?

## Step 2: Review Every Changed File

For every file in the diff, evaluate against ALL of the following dimensions. Do not skip dimensions. "Probably fine" is not an evaluation.

### Correctness

- Does the code do what the commit messages claim?
- Logic errors? Off-by-one? Inverted conditions?
- Boolean expressions correct? (De Morgan's law mistakes are common)
- Comparisons correct? (`==` vs `===`, `<` vs `<=`, wrong operand order)
- Return values used correctly? Promises awaited? Callbacks invoked?
- Race conditions or TOCTOU issues?
- Do loops terminate? Are break/continue correct?
- Regex patterns correct? Test mentally against expected AND unexpected inputs.
- String operations: encoding issues? Locale sensitivity? Template injection?
- Are numeric operations safe? Integer overflow, floating point comparison, division by zero?

### Security

- **Injection**: SQL, command, template, XSS, LDAP, header injection
- **Auth**: Are authentication and authorization checks present where needed? Can they be bypassed?
- **Secrets**: Any tokens, API keys, credentials, or connection strings hardcoded or logged?
- **Input validation**: Is all external input validated and sanitized at system boundaries?
- **Cryptography**: Secure algorithms? Cryptographically secure random where needed?
- **Path traversal**: Can user input influence file paths?
- **SSRF**: Can user input influence server-side request URLs?
- **Mass assignment**: Are object properties blindly copied from user input?
- **Data exposure**: Is PII logged? Are error messages leaking internals to clients?
- **Dependencies**: Are new dependencies from trusted sources? Known vulnerabilities?
- **Timing attacks**: Are sensitive comparisons (tokens, hashes) done in constant time?

### Architecture & Design

- Does this follow existing patterns in the codebase? If it deviates, is the deviation justified?
- Are boundaries between layers respected? (Domain vs. application vs. infrastructure)
- Is the abstraction level appropriate? Not over-engineered, not under-abstracted?
- Are new dependencies justified? Could this use what already exists?
- Is the code in the right place? Right module, right file, right layer?
- Are naming conventions consistent with the rest of the codebase?
- Does this change make future changes harder? Does it close doors unnecessarily?

### CLAUDE.md & ARCHITECTURE.md Compliance

Review the changes against every rule and constraint defined in the project's `CLAUDE.md` and `ARCHITECTURE.md` files (both repo-root and directory-level). These files are the project's source of truth for how code should be written.

- **Coding standards**: Does the code follow the declared style, patterns, and conventions? (e.g., preferred language idioms, error handling patterns, naming conventions, import ordering)
- **Architectural constraints**: Does the change respect declared boundaries, layers, and module responsibilities? Are prohibited patterns avoided?
- **Dependency rules**: Are dependency direction constraints honored? (e.g., "domain must not import infrastructure", "no direct DB access from handlers")
- **Testing requirements**: Does the change meet any declared testing standards? (e.g., "all public functions must be tested", "integration tests required for API changes")
- **Prohibited practices**: Is the code free of anything explicitly called out as forbidden? (e.g., `any` types, specific anti-patterns, banned libraries)
- **Required practices**: Does the code include anything declared as mandatory? (e.g., explicit error types, specific logging patterns, required middleware)

Flag every violation as a finding. CLAUDE.md/ARCHITECTURE.md rules are not suggestions — they are constraints with the same weight as correctness bugs.

### Types & Contracts

- Are types precise? No `any`, no loose signatures, no unwarranted type assertions.
- Is null/undefined handled explicitly? (Null guards, not optional chaining fallbacks)
- Are API contracts maintained? Do schema changes have migrations?
- Are generics used appropriately — not over-applied, not avoided when they'd help?
- Are union types exhaustively handled? (`switch` with `default: throw` or `satisfies never`)
- Do function signatures accurately describe behavior? Are side effects visible from the type?

### Error Handling

- Are errors handled at the right level? Not too early (swallowing), not too late (crashing).
- Are error messages actionable and contextual? Not generic "operation failed."
- Are errors typed or categorized appropriately?
- Is error handling missing on operations that can fail? (I/O, parsing, network, JSON)
- Are cleanup and rollback handled in error paths? (Finally blocks, defer, disposers)
- Are transactional operations rolled back on failure?
- Are errors propagated correctly, or silently swallowed? (`catch {}` is almost always wrong)
- Do retryable operations distinguish transient from permanent failures?

### Edge Cases

- Null, undefined, empty string, empty array, zero, negative numbers, NaN?
- Boundary values? (MAX_INT, empty collections, single-element arrays, off-by-one)
- Concurrent access? What if this runs twice simultaneously?
- External service down or slow? What's the timeout and fallback?
- Malformed input that passes validation? (Valid structure, nonsensical semantics)
- Retry safety? Is the operation idempotent?
- Unicode, special characters, very long strings, control characters?
- Clock skew, timezone edge cases, DST transitions (if time-related)?

### Performance

- N+1 query patterns?
- Unnecessary allocations in hot paths or tight loops?
- Database queries using indexes? New queries missing index coverage?
- Memory leaks? (Event listeners not removed, subscriptions not cleaned up, caches without eviction)
- Large datasets paginated?
- Expensive operations cached where appropriate?
- Algorithmic complexity acceptable for expected input sizes?
- Blocking operations on the event loop?
- Unnecessary serial execution where parallel would work?
- Large payloads transferred when only a subset is needed?

### Testing

- Are the changes tested? Unit tests? Integration tests?
- Do tests verify behavior, or just mirror the implementation?
- Are edge cases from the list above covered?
- Are error paths tested?
- Are tests deterministic? No time-dependent, order-dependent, or flaky assertions?
- Do existing tests still make sense after the change, or are they testing stale behavior?
- Are assertions specific? (Not just `toBeTruthy()` when you should check the value)
- Are test descriptions accurate? Does the test actually test what it says?

### Loose Ends

- **TODOs/FIXMEs**: Search changed files for `TODO`, `FIXME`, `HACK`, `XXX`, `PLACEHOLDER`
- **Dead code**: Functions, types, constants, or imports written but never used
- **Commented-out code**: Disabled code left behind
- **Placeholder values**: Hardcoded strings, magic numbers, dummy data that should be parameterized
- **Incomplete migrations**: Schema changes without data migration, feature flags without cleanup plan
- **Missing documentation**: Public API changes without updated docs, breaking changes without notes

## Step 3: Cross-Cutting Concerns

After reviewing individual files, check how the changes interact:

- Do the changed files interact correctly with each other?
- Are shared types and interfaces consistent across all consumers?
- Are database migrations ordered correctly?
- Are feature flags checked consistently across all relevant code paths?
- Could any of these changes break parts of the system that weren't modified?
- Are there implicit ordering dependencies between the changes?

## Step 4: Build Verification

- Does the code compile/type-check? Run the appropriate checker.
- Does linting pass?
- Do tests pass? Run the test suite (or relevant subset).
- Are there new warnings? Warnings often signal real problems.

## Step 5: Rate Confidence & Report

| Score | Meaning | Action |
| ----- | ------- | ------ |
| 10 | Perfect. Every dimension checked, build passes, no issues. | Done. |
| 9 | Confident. All verified. 1-point deduction for genuine unknowns only. | Done. |
| 7-8 | Issues found that can be fixed now. | Fix them, re-review. |
| 4-6 | Significant problems. Multiple dimensions have issues. | Fix them, re-review. |
| 1-3 | Fundamental problems. Won't compile, critical security issues, or major correctness bugs. | Keep working. |

Output your review:

```
## Branch Review: {branch name}

### Summary
**Intent**: {what the change does}
**Scope**: {files/modules affected}
**Commits**: {count}

### Findings

#### Critical (must fix before merge)
{Numbered list. Security vulnerabilities, correctness bugs, data loss risks, crash vectors.}

#### Important (should fix before merge)
{Numbered list. Missing error handling, untested code paths, type safety gaps, performance issues.}

#### Minor (consider fixing)
{Numbered list. Style inconsistencies, minor improvements, optional optimizations.}

#### Observations
{Things that aren't wrong but are worth noting — design trade-offs, elevated risk areas, future considerations.}

### CLAUDE.md / ARCHITECTURE.md Violations
{List every rule violated with the specific rule text and the violating code. "None found" if clean.}

### Dimensions Evaluated
{For each dimension in Step 2, one line: dimension name + what you checked + finding or "clean".
This proves you actually reviewed every dimension. Must include CLAUDE.md/ARCHITECTURE.md compliance.}

### Build Status
- **Type check**: {pass/fail}
- **Lint**: {pass/fail, warning count}
- **Tests**: {pass/fail, count}

---

## Confidence: {X}/10

{1-2 sentence justification. If 9+, state what the deduction is for. If <9, state what must be fixed.}
```

### If Confidence < 9

Fix the issues, then re-review the affected areas:

```
### Issues Fixed
1. {issue} — {what you did}
2. {issue} — {what you did}

## Re-Review After Fixes
{Verify the fixes and re-check affected dimensions}

## Updated Confidence: {X}/10
{justification}
```

Repeat until confidence reaches 9.

## Honesty Rules

- **Do not inflate your rating.** 8 is 8. Fix the issues.
- **Do not skip dimensions.** Every dimension in Step 2 must appear in your report.
- **The build must pass.** If it doesn't compile or tests fail, confidence caps at 5.
- **Critical findings block 9+.** Any unresolved critical finding means you keep working.
- **Review the diff, not the whole file.** Focus on what changed and what it interacts with. Read surrounding context for understanding, but findings should be about the changes.
- **"I think it's fine" is not 9.** 9 means "I verified it's fine."
- **The 1-point deduction is for genuine unknowns** — things that cannot be determined from static analysis. Not for things you could have checked but chose not to.
