# Local Development

> See also: [README.md](../../README.md), [docs/reference/tooling.md](../reference/tooling.md)
> See also: [docs/concepts/web.md](../concepts/web.md)

## Prerequisites

- Node.js 20.9+, pnpm 10.x
- Godot **4.7.2-stable** on PATH or `GODOT_BIN` (Windows PowerShell: `$env:GODOT_BIN = 'C:\path\to\Godot_v4.7.2-stable_win64_console.exe'`)
- Web export templates for `pnpm game:export:web` (`pnpm game:export:templates`)

## Play locally

```bash
pnpm install
pnpm game:export:web   # writes dist/game/web/
pnpm dev               # Next.js :3000 + Godot Web serve :8060
```

Open `http://localhost:3000` and press Play: `/play` on a loopback host redirects to `http://127.0.0.1:8060/` (WEB-005). For fast iteration, run the project from the Godot editor (F5) instead; the editor and the export run the same `main.tscn`.

## Validation

```bash
pnpm check    # import + lint + typecheck + format + docs/arch + tooling
pnpm test     # Godot harness + web coverage
pnpm verify   # check + test + build
RIPOSTE_SUITE=APP-E2E pnpm --filter @riposte/game test   # one game suite
```

## Cleanup

```bash
pnpm clean      # generated files (keeps node_modules)
pnpm reinstall  # clean + frozen-lockfile install
pnpm kill       # free leftover :3000 / :3001 / :8060 listeners
```

## Ports

| Port    | Use                                               |
| ------- | ------------------------------------------------- |
| `:3000` | Next.js dev                                       |
| `:3001` | Next.js fallback                                  |
| `:8060` | Godot Web serve (`dist/game/web/`, loopback only) |
