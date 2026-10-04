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

### WEB-005

Play admission. Every Play CTA MUST navigate to `/play`; only `resolvePlayAdmission` decides the destination. Loopback hosts → the local Godot export (`http://127.0.0.1:8060/` unless `NEXT_PUBLIC_LOCAL_PLAY_URL` overrides). Every other host → `NEXT_PUBLIC_PLAY_URL` (the itch page) when configured, else the `/play` explanation. Server builds decide in `proxy.ts` (307); static exports decide in `PlayGateway` with the same function. Components MUST NOT branch on hosts.

### WEB-006

Purpose-named destinations. Community (shown as Discord) and support (shown as Patreon) are configured by `NEXT_PUBLIC_COMMUNITY_URL` / `NEXT_PUBLIC_SUPPORT_URL` on the web and `CommunityLinks.COMMUNITY` / `SUPPORT` in the game. An unconfigured destination MUST render an announced "Coming soon" stub. URLs MUST NOT be invented or hardcoded elsewhere. Environment destinations MUST be validated: public URLs https only; local play may also use loopback http or a same-origin path; anything else is unconfigured.

---

## Simulation (SIM)

### SIM-001

Authoritative duel. Only `DuelSimulation.step(state, command_0, command_1)` advances authoritative state: exactly one `PlayerCommand` per fighter per 60 Hz tick (`SimulationTimebase`). The simulation MUST NOT read render delta, wall-clock time, input devices, Godot physics, scene nodes, or which source sent a command. `src/domain` and `content/rules` MUST NOT depend on application or presentation (SIM-PURITY lint). Same `DuelRules` + seed + commands MUST reproduce the same duel on every platform. Modes are configuration (rules + controllers), never separate simulations.

### SIM-002

Determinism proof. `StateHasher` MUST hash every authoritative field from exact IEEE-754 bits in a fixed order (SHA-256); presentation values MUST NOT enter the hash. `ReplayRecord` stores rules id + version, seed, and every tick's commands. `ReplayVerifier` re-simulates and MUST reject a rules mismatch, invalid rules, or a final-hash mismatch. Changing any rules value MUST bump `DuelRules.version`.

### SIM-MATH-001

Deterministic math. Simulation code MUST use `SimMath` (only + − × ÷ sqrt, each a separate operation) instead of engine trig / pow / lerp helpers (platform libm, FMA contraction), and scalar float fields instead of float32 engine vectors (`Vector2`, `Vector3`, …).

### SIM-RNG-001

Randomness. Duel physics uses no randomness. Decision makers (the CPU) MUST draw from `SeededRng`, the only domain wrapper of `RandomNumberGenerator`, seeded from the match seed. Global `randf()` / `randomize()` MUST NOT appear anywhere under `game/src/`.

### CMD-001

Command contract. `PlayerCommand` is the only input between a controller and the simulation (human, CPU, replay, future network). Movement is quantized to integer milli-units. Attack fields are edges within the tick window: pressed, released, canceled. Commands are untrusted; the simulation consumes `sanitized()` values. A cancel drops a charge without attacking (focus loss, touch cancel, pause).

### HITSTOP-001

Hitstop is wall-clock only. `FixedTickDriver.hold(seconds)` pauses tick consumption while impact feedback plays and MUST NOT change any tick-indexed result; headless runs and replays ignore it. A frame runs at most `MAX_CATCH_UP_TICKS`. Resuming from pause or a backgrounded tab MUST drop the backlog (`clear_backlog()`), never fast-forward.

---

## Combat (COMBAT)

### COMBAT-001

One-button language. A tap (release before `tap_threshold_ticks`) is exactly 0% charge and a 90° cut. Holding past the threshold charges and physically retracts the blade; release launches from the actual retracted angle with arc `90° + 90° × charge`. Swing direction comes from the blade's side of the facing, never a combo index. The sword persists where it stops. Commitment `K ∈ [0, 1]` reduces tracking and footwork; recovery follows from what actually happened (whiff, hit, deflection, bind).

### COMBAT-002

Swept collision. Blade and body contact MUST be detected across the whole tick motion in substeps sized so no blade point travels more than `substep_travel`; the earliest contact wins. Blades already touching at tick start MUST separate before a new impact registers. Godot physics MUST NOT decide a hit.

### COMBAT-003

Physical, relational consequences. Blade contact resolves as a 2D rigid impulse (speed, mass, effective inertia); low-energy contact binds. Parry and riposte are classified outcomes (the defender ends up threatening first), never inputs. Body damage comes from strike quality (closing speed × blade efficiency × edge alignment × stability × mass factor × target exposure) through a nonlinear curve; criticals come from convergence, never chance. Simultaneous body hits are evaluated against pre-hit state, so double hits stay symmetric.

---

## CPU (CPU)

### CPU-001

Fair CPU. The CPU MUST emit the same `PlayerCommand` a human would and obey the same rules. It feels its own body now and perceives its opponent only through a reaction-delay memory extrapolated by its anticipation skill; it MUST NOT read hidden state or future commands. Difficulty is `CpuProfile` data (reaction, cadence, anticipation, discipline), never stat or rule changes. Variety comes from `SeededRng`, so CPU play is reproducible per seed.

---

## Presentation (PRES)

### PRES-001

Presentation never authorizes outcomes. `SnapshotProjector` is the only place presentation reads `MatchState`, producing one immutable `PresentationSnapshot` per tick. `MatchPresenter`, proxies, directors, the HUD, and touch controls consume snapshots and events and emit intents or requests (hitstop, pause); they MUST NOT step, mutate, or read the simulation. `src/presentation` MUST NOT reference application classes (lint derives the ban from `class_name`s).

### PRES-KIT-001

One manifest per identity. Each content identity (fighter, weapon, arena) has exactly one `PresentationKit`: look (primitive or authored scene), animation clips, audio cues, VFX cues, and impact feel. Changing an identity's art, animation, or sound MUST be a kit edit (an authored `.tres` at `RiposteKits.AUTHORED_KIT_PATHS`), never a presenter or gameplay change. Generic presentation code MUST NOT name content identities. Debug builds fail closed on a missing kit; release builds degrade to a placeholder.

---

## UX (UX)

### UX-001

Accessible by construction. Every UI text/background pair MUST reach 4.5:1 and every essential non-text boundary 3:1 (WCAG 2.2), proven by tests over declared pairs (`RiposteTheme` pairs; `globals.css` tokens via `theme.test.ts`). Interactive targets are ≥ 48 UI units and one UI unit MUST be ≥ one CSS pixel (`UiScale`). State is never conveyed by color alone. Every shipped string MUST render in the shipped font. Every control has a visible label or an accessible name, and focus is always visible.

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

**Web/Vitest**: `coverage.include` MUST cover every in-scope web source file (`src/**/*.{ts,tsx}` minus tests, `*.d.ts`, and `src/test/`; routes and layouts included). Required: `thresholds: { 100: true, perFile: true }`. No v8/istanbul ignore comments in in-scope code. A mechanical manifest completeness check (`check-coverage-manifest.mjs`, run by `test:coverage`) MUST verify that the set of in-scope filesystem source files equals the set of files present in `coverage-final.json`. A new production file that no test imports MUST cause the manifest check to fail, not silently disappear from the coverage denominator.

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
