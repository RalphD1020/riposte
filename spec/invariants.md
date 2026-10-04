# Invariants

> Source: architectural constraints

Normative contracts for the Riposte project. RFC 2119: MUST / MUST NOT / SHOULD / SHOULD NOT / MAY.

Conflict rule: **spec > code > docs**. Code that violates this file is defective unless this file has been explicitly superseded.

---

## Monorepo (MONO)

### MONO-001

Sibling packages. `@riposte/web` (`apps/web`) and `@riposte/game` (`game`) MUST be siblings under the root monorepo. Next.js MUST NOT own the Godot runtime. Godot MUST NOT be initialized under `apps/web`.

### MONO-002

No-op ban. A package MUST NOT add a script that only echoes success to satisfy Turbo.

### MONO-003

Command-name abstraction. Root `dev` / `build` / `lint` / `typecheck` / `test` MUST invoke Turbo. Implementation technology MUST belong to each package.

---

## Documentation (DOC)

### DOC-001

Authority: spec > code > docs

Code that violates spec is defective. Docs that contradict code are stale.

---

## Web (WEB)

### WEB-001

Godot renderer. Riposte's canonical Godot renderer MUST be Compatibility.

Rationale: the browser is a first-class deployment target and Godot 4 Web exports use WebGL 2 through Compatibility. Forward+ and Mobile MUST NOT be used.

### WEB-002

Gameplay runtime language. Production Godot gameplay/runtime code MUST use typed GDScript.

C# MUST NOT enter the production game runtime without an architecture decision. Godot 4 C# cannot export to Web.

### WEB-003

Web threading. Riposte uses Godot's single-threaded Web export (Compatibility / WebGL 2.0). The committed Web preset MUST enable both `vram_texture_compression/for_desktop` and `vram_texture_compression/for_mobile`.

### WEB-004

itch.io distribution. itch.io hosts the Godot Web export (`dist/game/web/`), not the Next.js app.

---

## Git (GIT)

### GIT-001

Agents MUST NOT create commits unless the user explicitly instructs it in the current request.

---

## Coverage (COVERAGE)

### COVERAGE-001

Every non-UX/UI production source file MUST achieve 100% line, function, and branch coverage individually. Web/TypeScript code MUST additionally achieve 100% statement coverage. Coverage is necessary but not sufficient: every behavioral invariant MUST also have an independent, non-vacuous behavioral test.

Coverage MUST be measured per file. Do not use project-average 100%. One file at 99.9% means the gate is RED. No `autoUpdate`. No coverage-ignore comments. No exclusions inside covered roots merely because something is difficult to test.

**Covered scope** includes: authoritative simulation/domain, deterministic math, combat, AI/targeting, economy, production, placement/build validation, game state machines, commands, config resolution, content validation, replay/hash/serialization, application orchestration, interaction/authorization logic, matchmaking, ELO calculation, and nonvisual web application/domain logic.

**Excluded from numeric 100%** (by architectural scope only): pure UI layout, purely visual presentation, VFX/SFX, shaders, animation/art polish, purely decorative camera feel, third-party addons, generated code, test code itself.

If code affects authoritative state, permissions, simulation outcome, economy, progression, win/loss, deterministic hashes, matchmaking results, ELO ratings, or shipping product behavior, it MUST NOT reside in a coverage-excluded directory.

**Web/Vitest**: `coverage.include` MUST explicitly enumerate all in-scope web source files. Required: `thresholds: { 100: true, perFile: true }`. No v8/istanbul ignore comments in in-scope code. A mechanical manifest completeness check MUST verify that the set of in-scope filesystem source files equals the set of files present in `coverage-final.json`. A new production file that no test imports MUST cause the manifest check to fail, not silently disappear from the coverage denominator.

**GDScript**: 100% measured line/function/branch coverage is required for in-scope non-UX/UI production scripts before Mechanical Freeze closes. Do not rewrite the existing deterministic harness merely for instrumentation. Mechanical Freeze stays OPEN until measurement exists.

**Content coverage**: catalog-driven content validators MUST cover 100% of canonical entries. A newly registered content item MUST automatically enter the test denominator.

---

## Testing (TEST)

### TEST-TRUTH-001

Every behavioral test MUST explicitly assert its fixture (ARRANGE), the perturbation (PERTURB), run production code (ACT), and verify the contract (ASSERT).

A test's function name and comments are not evidence. Preconditions MUST be asserted before the oracle is invoked.

**Anti-vacuity rules** (test lint MUST reject):

- `assert_true(true)` / equivalent tautologies
- disabled/skipped tests in covered suites
- zero-assertion test functions
- commented-out assertions
- warning-only correctness checks
- coverage-ignore directives
- ignored fallible fixture setup

**Expected results MUST be independent** of production logic under test.

Do NOT use `assert()` for required release behavior. Godot strips `assert()` in non-debug builds. Production handling MUST use explicit `if/else` branches that are testable and present in shipping builds.

### ZERO-TOLERANCE-001

Zero `@warning_ignore`; Godot default warnings are errors. The repository MUST contain zero `@warning_ignore`, `warning_ignore_start`, or `warning_ignore_restore` directives.
