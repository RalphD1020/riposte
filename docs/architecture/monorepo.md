# Monorepo

> See also: [README.md](../../README.md)
> See also: [spec/invariants.md](../../spec/invariants.md)
> See also: [docs/reference/godot.md](../reference/godot.md)
> See also: [docs/reference/tooling.md](../reference/tooling.md)
> Source: `pnpm-workspace.yaml`, `turbo.json`, `game/package.json`, `apps/web/package.json`

Authority: **spec > code > docs > .impl** (DOC-001).

## Topology

```text
riposte/
├── apps/web/          @riposte/web   Next.js site
├── game/              @riposte/game  Godot 4.7.x / 4.7.2-stable
├── packages/          future shared TypeScript packages
├── docs/ spec/ examples/ scripts/
└── dist/              generated artifacts (gitignored)
    └── game/web/      canonical Godot Web export (`pnpm game:export:web`)
```

`apps/web` and `game` are siblings (MONO-001). Root pnpm/Turbo owns orchestration (MONO-003).

## Workspace

```yaml
packages:
  - "apps/*"
  - "packages/*"
  - "game"
```

`game/package.json` exists so `@riposte/game` is a workspace member. `lint` is source-policy scanners (`lint.mjs`). `typecheck` / `test` invoke Godot `--script` checkers. `check` is a sequential Godot runner (version → `--import` → lint → scripts → tooling). Godot Turbo tasks are uncached. Root `lint` / `typecheck` / `test` use Turbo; root `test:tooling` is the fail-fixture gate; root `check` / `build` / `verify` are synchronous report runners (`verify` = check + test + build). Do not hardcode `@riposte/web` or `@riposte/game` in root scripts. Do not add no-op `dev` / `build` / `format` scripts (MONO-002). `@riposte/game` `dev` serves `dist/game/web/` on loopback `:8060`. Godot Web artifact is `pnpm game:export:web`, not site `build`.

## Task contract

TypeScript packages that measure coverage expose `test:coverage` (100% perFile). `@riposte/game` exposes `test` / `test:headless` (Godot harness) and MUST NOT name the harness `test:coverage`. Root `pnpm test` is `turbo run test test:coverage` (harness + measured web). Root `pnpm test:coverage` is measured coverage only (web today). All packages also expose `dev`, `build` (when real), `typecheck`, `lint`, and format scripts per MONO-002.

Turbo skips packages that omit a script. Root `pnpm lint` must not hardcode `--filter @riposte/web`.

## itch.io

The itch.io HTML5 upload is the Godot Web export, not a Next.js static game. Owned-web Play refers to that instance via `NEXT_PUBLIC_PLAY_URL` (stubbed empty until published). Localhost Play navigates to the standalone `:8060` export (WEB-005, [docs/concepts/web.md](../concepts/web.md)). `pnpm build:static` exports the **website** only.

## Cleanup

`pnpm clean` removes generated output (`.turbo`, `.next`, `dist`, `coverage`, `game/.godot`). `pnpm reinstall` also removes `node_modules` and runs `pnpm install --frozen-lockfile`. The lockfile is kept.

`pnpm kill` is a recovery tool that frees leftover listeners on `:3000`, `:3001`, and `:8060`. It is not part of normal shutdown. See [docs/guides/local-dev.md](../guides/local-dev.md).
