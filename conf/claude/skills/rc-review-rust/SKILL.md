---
name: rc-review-rust
description: "Rust-specific code review. Two modes: (1) branch diff review (default) reviews current branch changes against base, (2) full codebase audit when user says 'full audit', 'audit the codebase', 'review everything', etc. Reviews against idiomatic Rust best practices — ownership, error handling, performance, types, testing, documentation, linting, and concurrency. Rates confidence 1-10 and fixes issues until 9+."
allowed-tools: Read, Glob, Grep, Bash, LSP, Edit, Write, Agent
---

# Rust Code Review

You are reviewing Rust code. This is adversarial review grounded in idiomatic Rust — your job is to catch ownership mistakes, performance traps, error handling gaps, and unsafe patterns before they ship.

**You may not stop until your confidence reaches at least 9/10.** The 1-point deduction is reserved for things you genuinely cannot determine from static analysis (runtime behavior under load, production data edge cases, external service interactions). It is NOT for things you could have checked but didn't.

## Mode Selection

This skill runs in one of two modes. Select based on the user's request:

### Branch Diff Mode (default)

Use this when the user invokes the skill without qualification, or says things like "review this branch", "review my changes", etc. Scope is limited to changed files on the current branch vs the base branch.

### Full Codebase Audit Mode

Use this when the user says something to the effect of: "full audit", "audit the codebase", "review everything", "review the whole project", "full review", "audit all files". Scope is the **entire codebase** — every `.rs` file, every `Cargo.toml`, every configuration file.

## Step 1: Understand the Target

Before reviewing anything, understand what you're looking at.

### Branch Diff Mode

1. **Identify the base branch**: Run `git merge-base main HEAD` then `git log --oneline main..HEAD` to see all commits on this branch.
2. **Get the full diff**: Run `git diff main...HEAD -- '*.rs' '*.toml'` to see the complete Rust change set. Also check for changes to `Cargo.lock`.
3. **Read commit messages**: They tell you the intent. If they don't, that's a finding.
4. **Identify the scope**: Which crates, modules, and public APIs changed? Is this a library, binary, or both?
5. **Read project standards**: Find and read `CLAUDE.md`, `ARCHITECTURE.md`, `clippy.toml`, `rustfmt.toml`, and lint configuration in `Cargo.toml` (both `[lints]` and `[workspace.lints]` sections). Every rule in these files is a review criterion.

Write a brief summary:

- **Intent**: What is this change trying to accomplish?
- **Scope**: What crates/modules are touched? Library, binary, or both?
- **Blast radius**: What could break if this is wrong? What downstream consumers exist?

### Full Codebase Audit Mode

1. **Map the project**: Run `find . -name '*.rs' | head -200` and `find . -name 'Cargo.toml'` to understand the full project structure. Identify all crates, binaries, and libraries.
2. **Read project standards**: Find and read `CLAUDE.md`, `ARCHITECTURE.md`, `clippy.toml`, `rustfmt.toml`, and lint configuration in all `Cargo.toml` files. Every rule is a review criterion.
3. **Read every `.rs` file**: Use agents to parallelize reading across crates/modules. Every file is in scope.
4. **Identify the architecture**: What are the crate boundaries? What are the public APIs? How do crates depend on each other?

Write a brief summary:

- **Project**: What does this project do?
- **Structure**: What crates/modules exist? Library, binary, or both?
- **Architecture**: How are the crates organized? What are the key abstractions?
- **Dependencies**: What external crates are used? Are they appropriate?

## Step 2: Review the Rust Code

**Branch Diff Mode**: For every `.rs` file in the diff, evaluate against ALL of the following dimensions.
**Full Codebase Audit Mode**: For every `.rs` file in the project, evaluate against ALL of the following dimensions. Use agents to parallelize across crates/modules — one agent per crate or major module.

Do not skip dimensions. "Probably fine" is not an evaluation.

### Ownership & Borrowing

- Are references (`&T`, `&str`, `&[T]`) used instead of owned types (`String`, `Vec<T>`) where the function only needs read access?
- Are there unnecessary `.clone()` calls? Could the function take `&T` instead of requiring ownership?
- Is cloning happening inside loops? (`.map(|x| x.clone())` should be `.cloned()` or `.copied()`)
- Are function signatures asking for `Vec<T>` or `&Vec<T>` when `&[T]` would suffice? `String` or `&String` when `&str` would work? (Rust auto-derefs, so prefer the slice/str form.)
- If a function clones a reference argument internally, should the caller pass ownership instead?
- Are `Copy` types passed by reference unnecessarily? Small types (`u32`, `bool`, `f32`, small structs <= 24 bytes) should be passed by value.
- Is `Cow<'_, T>` appropriate where ownership is conditionally needed?
- Are large types (> 512 bytes) being passed by value when a reference would avoid the copy?
- Is `.clone()` on `Arc`/`Rc` used correctly for shared ownership, not as a lazy escape from borrow checker fights?

### Idiomatic Patterns

- **Option/Result handling**: Is the right pattern used for each case?
  - `match` for pattern matching against inner types or complex transformations
  - `let Ok(x) = expr else { return/break/continue }` for early returns with simple divergence
  - `if let` when the else branch needs computation
  - `?` when the caller should handle the error
  - `.ok()`, `.ok_or()`, `.ok_or_else()` instead of verbose `match` for Option/Result conversion
- **Early allocation prevention**: Are `or`, `map_or`, `unwrap_or`, `ok_or` used with heap-allocating expressions? These should be `_else` variants (`or_else`, `map_or_else`, `unwrap_or_else`, `ok_or_else`) when the fallback allocates or calls a function. Is `unwrap_or_default()` used instead of `unwrap_or(Vec::new())` / `unwrap_or(String::new())` etc.?
- **Iterator vs for**: Are iterators used for collection transforms? Are `for` loops used when early exits (`break`, `continue`, `return`) or side effects dominate?
  - Is `.sum()` used instead of `.fold()` for summing?
  - Are intermediate `.collect()` calls avoided when the iterator could be passed directly?
  - Is `.iter()` preferred over `.into_iter()` when ownership isn't needed? Especially for `Copy` inner types (`Vec<u32>`, `Vec<bool>`, etc.) where `.iter()` is always sufficient.
  - Are iterator chains formatted one method per line?
- **Import ordering**: Are `use` declarations grouped correctly? (`std` -> external crates -> workspace crates -> `super::` -> `crate::`)
- **Error inspection**: Is `inspect_err` + `map_err` used for logging and transforming errors, instead of verbose match blocks?
- **Comment prefixes**: Are comments prefixed with their category? `// SAFETY:` for unsafe justification, `// PERF:` for performance reasoning, `// CONTEXT:` for design context. Link to ADRs or Design Docs when deeper justification is needed.

### Error Handling

- Does every fallible function return `Result<T, E>` with a meaningful error type?
- Is `panic!()` replaced with `todo!()` (unfinished code), `unreachable!()` (proven impossible), or `unimplemented!()` (intentionally not yet done) where appropriate?
- Are `unwrap()` and `expect()` absent from production code? (Acceptable only in tests, assertions, or provably infallible cases with a comment.)
- Are `let Ok(..) = expr else { return }` patterns used instead of `unwrap` for early returns?
- Is `thiserror` used for library/crate-level error types — both enum errors (multiple variants) and struct errors (single error type per module) — with `#[error(...)]` messages and `#[from]` conversions?
- Is `anyhow` confined to binary entry points and test helpers — never in library code?
- Are error hierarchies structured with nested enums and `#[from]` for layered systems?
- Is `?` used to propagate errors instead of verbose `match` chains?
- Do error messages provide actionable context? Not generic "operation failed."
- Are errors typed or categorized appropriately for the caller to act on?
- Do async errors implement `Send + Sync + 'static` where needed across `.await` boundaries?
- Is `Box<dyn std::error::Error>` avoided in library code?
- Are error paths tested? Do tests exercise error cases and validate error messages?

### Types, Generics & Dispatch

- Are generics used appropriately — not over-applied, not avoided when they'd help?
- Is static dispatch (`impl Trait`, `<T: Trait>`) the default? Dynamic dispatch (`dyn Trait`) only where runtime polymorphism is genuinely needed?
- For `dyn Trait`: Is the trait object-safe? (No generic methods, no `Self: Sized`, no methods returning `Self`, methods use `&self`/`&mut self`/`self`)
- Is `&dyn Trait` used over `Box<dyn Trait>` when ownership isn't needed?
- Is `Arc<dyn Trait + Send + Sync>` used for shared access across threads?
- Are there premature `Box<dyn Trait>` inside structs that could use a generic parameter instead? If `dyn Trait` must be in a public API, is it boxed at the boundary rather than internally?
- Is the type state pattern used where it would prevent illegal states at compile time? Is it avoided where it would add complexity without safety benefit?
- Are `PhantomData` markers used correctly for type-state implementations?
- Are enums sized appropriately? (Check for `large_enum_variant` — large variants should be `Box`ed)
- Is `#[non_exhaustive]` considered for public enums that may grow?

### Performance

- **Don't guess, measure.** Are performance "optimizations" evidence-based, not speculative?
- Are there redundant clones? (Run `cargo clippy` — `redundant_clone` lint)
- Is `#[inline]` used only where benchmarks prove it beneficial? (Rust is good at inlining without hints)
- Are large stack allocations boxed? (e.g., `Box::new([0u8; 65536])` first allocates on stack — use `vec![0; 65536].into_boxed_slice()` instead)
- Are iterators used for zero-cost abstraction instead of manual loops with intermediate collections?
- Is `.collect()` avoided when the iterator itself could be passed to the consumer?
- For hot paths: are allocations minimized? Reuse buffers where possible?
- Are `Cow<'_, T>` or borrowed slices used to avoid unnecessary allocation?
- Stack vs heap: are small `Copy` types on the stack? Are recursive/large data structures heap-allocated?
- Is `smallvec` considered for arrays that are usually small but occasionally large?

### Pointers & Concurrency

- Is the correct pointer type used for the use case?
  - `&T` / `&mut T` for borrowing
  - `Box<T>` for single-owner heap allocation
  - `Rc<T>` for single-thread shared ownership, `Arc<T>` for multi-thread
  - `Cell<T>` / `RefCell<T>` for single-thread interior mutability
  - `Mutex<T>` / `RwLock<T>` for thread-safe interior mutability
  - `OnceCell` / `OnceLock` / `LazyCell` / `LazyLock` for initialization patterns
- Are `Send` and `Sync` bounds correct? Data shared across threads must be `Send + Sync`.
- Is `Rc` accidentally used where `Arc` is needed (multi-threaded context)?
- Is `RefCell` used in a multi-threaded context? (It should be `Mutex` or `RwLock`.) Even in single-threaded code, is the runtime panic risk of `RefCell` acknowledged? (Borrowing mutably while already borrowed panics at runtime.)
- Are `Mutex` locks held across `.await` points? (Use `tokio::sync::Mutex` or restructure.)
- Are raw pointers (`*const T`, `*mut T`) confined to FFI boundaries with `unsafe` blocks and `// SAFETY:` comments?
- Is `unsafe` code minimized, well-documented with `// SAFETY:` comments, and encapsulated behind safe APIs?

### Testing

- Are tests present for new/changed functionality?
- Do test names read as sentences describing the desired behavior? (Not `test_add_happy_path` but `returns_sum_of_two_positive_integers`)
- Are tests organized in `#[cfg(test)] mod test` with nested modules per unit of work?
- Does each test verify **one behavior** with ideally **one assertion**?
- Are `assert!` and `assert_eq!` messages formatted with the actual state for debugging? (`assert_eq!(result, expected, "got {result:?} for input {input:?}")`)
- Is `assert!(matches!(value, Pattern))` used for pattern matching assertions where exact equality isn't needed?
- Are error paths tested? Do tests call `.unwrap_err()` and verify the error variant/message?
- Is `#[should_panic]` used only when panic is the intended behavior?
- Are `#[ignore = "reason"]` tests actually tracked (linked to an issue)?
- For public APIs: are there `/// # Examples` doc tests that run with `cargo test`? Are `compile_fail` and `no_run` attributes used in doc examples to demonstrate wrong usage or side-effecting code?
- Are snapshot tests (`cargo insta`) used appropriately for complex output — not for simple primitives?
- Are snapshot tests small, named, and using redactions for unstable fields (timestamps, UUIDs)?
- Do integration tests live in `tests/` and only use the public API?

### Linting Discipline

- Does the code pass `cargo clippy --all-targets --all-features -- -D warnings`?
- Are clippy lint suppressions using `#[expect(...)]` (not `#[allow(...)]`) with a comment explaining why?
- Are these critical lints clean?
  - `redundant_clone` — unnecessary `.clone()` calls
  - `needless_borrow` — redundant `&` borrowing
  - `large_enum_variant` — enums with oversized variants
  - `unnecessary_wraps` — functions that always return `Some`/`Ok`
  - `clone_on_copy` — `.clone()` on `Copy` types
  - `needless_collect` — collecting iterators unnecessarily
  - `map_unwrap_or` / `unnecessary_map_or` — simplifies nested Option/Result handling
  - `manual_ok_or` — suggests `.ok_or_else()` instead of verbose `match`
- Are new `#[allow(...)]` or `#[expect(...)]` attributes justified and documented?
- Is the `Cargo.toml` lint configuration (`[lints.clippy]`, `[lints.rust]`) respected?
- Does `rustfmt` pass? Is `cargo +nightly fmt` used if custom import ordering is configured?

### Security

- Are user inputs validated at system boundaries?
- Is `unsafe` code audited for memory safety? Buffer overruns, use-after-free, dangling pointers?
- Are secrets, tokens, or credentials absent from source code and logs?
- Are cryptographic operations using secure primitives? (No hand-rolled crypto)
- Is path traversal prevented when user input influences file paths?
- Are dependencies from trusted sources? Check for typosquatting or known vulnerabilities.
- For FFI: are null pointer checks present? Are buffer lengths validated?
- Are sensitive comparisons (tokens, hashes) done in constant time?

### Loose Ends

- **TODOs/FIXMEs**: Search changed files for `TODO`, `FIXME`, `HACK`, `XXX`, `PLACEHOLDER` — each must reference a tracked issue.
- **Dead code**: Functions, types, constants, or imports written but never used. (`#[allow(dead_code)]` is a smell.)
- **Commented-out code**: Delete it. Version control remembers.
- **Placeholder values**: Hardcoded strings, magic numbers, dummy data that should be constants or configuration.
- **Incomplete migrations**: Schema changes, API changes without version bumps, breaking changes without migration path.
- **Missing `Cargo.toml` updates**: New dependencies not declared, version bumps missing, features not gated.

## Step 3: Cross-Cutting Concerns

After reviewing individual files, check how the changes interact:

- Do trait implementations satisfy all required bounds across the crate? (A new `Send` requirement propagates.)
- Are error types composable across module boundaries? (Does `#[from]` chain correctly?)
- Are public API changes backwards-compatible? If breaking, is the version bumped?
- Do feature flags gate code consistently? No dead code paths when a feature is disabled?
- Are `Cargo.toml` dependency versions consistent across workspace members?
- Could any of these changes break downstream crates or binaries that weren't modified?
- Are type-state transitions consistent across modules that share the same state types?

## Step 4: Build Verification

Run these in order. Each must pass.

1. **Type check**: `cargo check --all-targets --all-features`
2. **Lint**: `cargo clippy --all-targets --all-features -- -D warnings`
3. **Format**: `cargo fmt --check` (or `cargo +nightly fmt --check` if nightly formatting is configured)
4. **Tests**: `cargo test --all-features` (and `cargo test --doc` if using nextest)
5. **Warnings**: Review output of all above for warnings. Warnings are findings.

If any step fails, that is a finding. Fix it before proceeding.

## Step 5: Rate Confidence & Report

| Score | Meaning | Action |
| ----- | ------- | ------ |
| 10 | Perfect. Every dimension checked, build passes, no issues. | Done. |
| 9 | Confident. All verified. 1-point deduction for genuine unknowns only. | Done. |
| 7-8 | Issues found that can be fixed now. | Fix them, re-review. |
| 4-6 | Significant problems. Multiple dimensions have issues. | Fix them, re-review. |
| 1-3 | Fundamental problems. Won't compile, critical safety issues, or major correctness bugs. | Keep working. |

Output your review:

```
## Rust Review: {branch name or project name}
**Mode**: {Branch Diff | Full Codebase Audit}

### Summary
**Intent**: {what the change does / what the project does}
**Scope**: {crates/modules affected, library vs binary}
**Commits**: {count, branch diff mode only}

### Findings

#### Critical (must fix before merge)
{Numbered list. Safety/soundness issues, undefined behavior, data races, correctness bugs, production unwrap/expect.}

#### Important (should fix before merge)
{Numbered list. Missing error handling, unnecessary cloning, wrong dispatch choice, untested code paths, missing docs on public API.}

#### Minor (consider fixing)
{Numbered list. Style inconsistencies, suboptimal patterns, import ordering, naming.}

#### Observations
{Things that aren't wrong but are worth noting — design trade-offs, performance considerations, future refactoring opportunities.}

### Dimensions Evaluated
{For each dimension in Step 2, one line: dimension name + what you checked + finding or "clean".
This proves you actually reviewed every dimension.}

### Build Status
- **Type check** (`cargo check`): {pass/fail}
- **Lint** (`cargo clippy`): {pass/fail, warning count}
- **Format** (`cargo fmt`): {pass/fail}
- **Tests** (`cargo test`): {pass/fail, count}

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
- **The build must pass.** If `cargo check` or `cargo test` fails, confidence caps at 5.
- **Critical findings block 9+.** Any unresolved critical finding means you keep working.
- **Branch Diff Mode: Review the diff, not the whole file.** Focus on what changed and what it interacts with. Read surrounding context for understanding, but findings should be about the changes.
- **Full Codebase Audit Mode: Review everything.** Every file is in scope. Use agents to parallelize. Prioritize critical paths and public APIs first, then internals.
- **"I think it's fine" is not 9.** 9 means "I verified it's fine."
- **The 1-point deduction is for genuine unknowns** — things that cannot be determined from static analysis. Not for things you could have checked but chose not to.
- **Rust-specific: `unsafe` blocks require proof.** Every `unsafe` block in the diff must have a `// SAFETY:` comment that you have verified. Missing safety comments are Critical findings.
- **Rust-specific: `unwrap()`/`expect()` in non-test code is a Critical finding** unless accompanied by a proof comment explaining why it cannot fail.
