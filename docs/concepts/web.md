# Web

> See also: [README.md](../../README.md)
> See also: [docs/architecture/monorepo.md](../architecture/monorepo.md)
> Source: `apps/web/`

## Structure

The `@riposte/web` package is a Next.js App Router application.

## Play Admission

The website provides a gateway to the game. On localhost, this redirects to the Godot Web serve at `:8060`. In production, it links to the published game.

## Static Export

`pnpm build:static` produces a static site for website hosting. This is NOT the game — the game is the Godot Web export at `dist/game/web/`.
