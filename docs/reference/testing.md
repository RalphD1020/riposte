# Testing

> See also: [spec/invariants.md](../../spec/invariants.md) (COVERAGE-001, TEST-TRUTH-001)
> See also: [docs/architecture/monorepo.md](../architecture/monorepo.md)
> Source: `vitest.config.ts`, test suites

## Coverage Requirements

| Package         | Tool                                              |
| --------------- | ------------------------------------------------- |
| `@riposte/web`  | Vitest + `@vitest/coverage-v8`, 100% thresholds   |
| `@riposte/game` | Godot headless harness (behavioral, not measured) |

`pnpm test` is `turbo run test test:coverage` (Godot harness + website v8 100%). `pnpm test:fast` is `turbo test` (harness + web without coverage). `pnpm test:coverage` is measured coverage only (web today; no game script until GDScript is measured). `pnpm check` runs `--import`, lint, typecheck, docs, arch, and `test:tooling`. It MUST NOT re-run the full behavior suites. `pnpm verify` is check then test then build.

## Web Coverage Scope

`@riposte/web` includes `src/**/*.{ts,tsx}` except tests, `*.d.ts`, and `src/test/**`. Do not exclude pages to dodge coverage.

**Thresholds**: `100: true, perFile: true` — every file must hit 100% statements, branches, functions, and lines.

**Manifest check**: `apps/web/scripts/check-coverage-manifest.mjs` verifies that every in-scope source file appears in the coverage report. A new file with no test imports MUST fail the manifest check, not silently disappear from coverage.

## GDScript Coverage

`@riposte/game` `test` / `test:headless` is the behavioral harness (suites expected to pass). This is **not** measured GDScript line coverage. Do not add `test:coverage` until a collector measures it.

The gates are explicit:

- **Behavioral gate**: all suites green, zero engine ERROR/WARNING.
- **Web coverage gate**: 100% scoped non-visual production lines (perFile).
- **GDScript coverage gate**: 100% line/function/branch (NOT VERIFIED until collector exists).

## Test Design (TEST-TRUTH-001)

Every behavioral test MUST:

1. **ARRANGE** — set up fixture, assert preconditions
2. **PERTURB** — apply the change being tested
3. **ACT** — run production code
4. **ASSERT** — verify the contract

Anti-vacuity rules:

- No `assert_true(true)` or tautologies
- No disabled/skipped tests
- No zero-assertion functions
- No commented-out assertions
- No coverage-ignore directives

Do not add tests whose only job is to inflate coverage.

## Production Scope

If code affects any of these, it MUST be in the covered scope:

- Authoritative state
- Simulation outcome
- Economy / progression
- Win/loss determination
- Matchmaking results
- ELO calculations
- Deterministic hashes
- Shipping product behavior

## Commands

```bash
pnpm test                    # Full test + coverage
pnpm test:fast               # Tests without coverage
pnpm test:coverage           # Coverage only
pnpm --filter @riposte/web test:coverage
```
