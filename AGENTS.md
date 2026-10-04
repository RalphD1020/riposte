# AI Agent Instructions — Riposte

> Humans own software. AI proposes; CI enforces.

## Where truth lives

| Need                     | Read                                      |
| ------------------------ | ----------------------------------------- |
| Universal guidelines     | [README.md](./README.md)                  |
| Durable explanation      | [docs/](./docs/)                          |
| Normative contracts      | [spec/](./spec/)                          |
| Consumer proofs          | [examples/](./examples/)                  |
| Local plans (gitignored) | `.impl/` (never link from committed docs) |

```text
spec > code > docs > .impl
```

If code violates spec, the implementation is defective unless the spec has been superseded.

## Laws

0. Inspect `docs/` and `spec/` before implementing.
1. `.impl/` is temporary working memory. Promote durable facts to `docs/`, `spec/`, or `examples/`.
2. Committed markdown must not reference `.impl/`.
3. COVERAGE-001: 100% line/function/branch/statement coverage per file on all non-UX/UI production sources (TypeScript: `perFile: true`). GDScript coverage: behavioral gate green until measured by a real collector. Do not weaken thresholds or use ignore/exclude/expect/disable. TEST-TRUTH-001: every behavioral test asserts its fixture (ARRANGE), perturbation (PERTURB), production code (ACT), contract (ASSERT). Do not use `assert()` for release behavior. ZERO-TOLERANCE-001: zero `@warning_ignore`; Godot default warnings are errors.
4. Use root commands (`pnpm check`, `pnpm test`, `pnpm lint`, `pnpm typecheck`) for validation.
5. Package task names are the monorepo abstraction. Do not hardcode root scripts to `@riposte/web` or `@riposte/game`.
6. `apps/web` and `game` are siblings. Next.js must not own the Godot runtime. Do not put `.gd`, `.tscn`, `.tres`, or `project.godot` under `apps/web`.
7. Never add a no-op package script merely to satisfy Turbo (MONO-002).
8. GIT-001. Agents MUST NOT create commits unless the user explicitly instructs it in the current request.

## Riposte game work

- Read `.impl/INDEX.md` when available.
- Normative game contracts live in `spec/`.
- Durable explanations live in `docs/`.
- Never introduce committed references to `.impl/`.
- Use Compatibility for Web (WEB-001).
- Follow [docs/reference/godot.md](./docs/reference/godot.md) for Godot conventions. Authoritative runtime: Godot **4.7.2-stable**.

## Coverage

Measured `src` in packages that define `test:coverage` must stay at 100% statements, branches, functions, and lines per file. Do not maintain coverage through ignore/exclude/expect/disable or meaningless execution-only tests.

When 100% coverage exposes an uncovered branch: (1) test reachable behavior, (2) test the authoritative failure boundary, or (3) delete unreachable code. Do not rewrite conditionals solely to change instrumentation.

Matchmaking, ELO systems, and all production logic affecting outcomes MUST be in covered scope.

## Commands

```bash
pnpm check
pnpm test
pnpm verify
pnpm docs:check
pnpm arch:check
```

`lint` is static policy. `typecheck` is parse/load. `test` is behavior. `check` is the non-artifact static/load/tooling gate (Godot `--import` first; includes `test:tooling`; does not re-run behavior suites). `build` is artifacts only. `verify` is check then test then build. Command contract: [docs/reference/tooling.md](./docs/reference/tooling.md).

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": false` in the root `turbo.json` or `turbo.jsonc` to opt out; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
