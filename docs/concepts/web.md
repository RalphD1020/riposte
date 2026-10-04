# Web

> See also: [README.md](../../README.md), [docs/architecture/monorepo.md](../architecture/monorepo.md)
> See also: [spec/invariants.md](../../spec/invariants.md) — WEB-004, WEB-005, WEB-006, UX-001
> Source: `apps/web/`

`@riposte/web` is the Next.js App Router gateway: what Riposte is, how to play, community destinations, and the Play button. It never hosts or initializes the Godot runtime (MONO-001).

## Routes

| Route                            | View                                                       | Notes                                                              |
| -------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------ |
| `/`                              | `HomePage`                                                 | One primary action (Play Riposte), how to play, community stubs    |
| `/play`                          | `PlayPage` → `PlayGateway`                                 | Play admission (WEB-005)                                           |
| `/how-to-play`                   | `HowToPlayPage`                                            | Mirrors the in-game How to Play (copy kept in sync with `AppCopy`) |
| `/about`                         | `AboutPage`                                                | What this release is                                               |
| not found / error / global error | `not-found.tsx`, `error.tsx` (`retry`), `global-error.tsx` | Plain language; never the raw error message                        |

Every route prerenders as static content; the layout reads no request data.

## Play admission (WEB-005)

Every Play CTA is a plain link to `/play`. `resolvePlayAdmission(hostname, config)` (`apps/web/src/config/runtimeConfig.ts`) decides:

| Host                            | Destination                                                                           |
| ------------------------------- | ------------------------------------------------------------------------------------- |
| `localhost`, `127.0.0.1`, `::1` | Local Godot export, `http://127.0.0.1:8060/` (`NEXT_PUBLIC_LOCAL_PLAY_URL` overrides) |
| anything else                   | `NEXT_PUBLIC_PLAY_URL` (itch page, https only) or the "not published yet" page        |

- Server builds: `apps/web/src/proxy.ts` 307s `/play` from the Host header.
- Static exports (`pnpm build:static`, no proxy): `PlayGateway` makes the same decision from `window.location.hostname` and replaces the location, with a visible fallback link. Next warns that static export disables the proxy; that is expected.

## Configuration

`runtimeConfig.ts` is the only module that reads `process.env.NEXT_PUBLIC_*` (each by literal name, so Next inlines it). Values are validated (WEB-006): public URLs https only; local play may be loopback http or a same-origin path; `/play` itself and anything else is unconfigured. See `apps/web/.env.example`.

| Variable                                                | Use                                            |
| ------------------------------------------------------- | ---------------------------------------------- |
| `NEXT_PUBLIC_PLAY_URL`                                  | Public itch page (empty until published)       |
| `NEXT_PUBLIC_LOCAL_PLAY_URL`                            | Local game override                            |
| `NEXT_PUBLIC_COMMUNITY_URL` / `NEXT_PUBLIC_SUPPORT_URL` | Discord / Patreon; empty renders "Coming soon" |
| `NEXT_PUBLIC_APP_VERSION`                               | Set by `next.config.ts` from `package.json`    |

## Styles and copy

- One stylesheet: `apps/web/src/app/globals.css` (`@theme` tokens + semantic classes; JSX never uses utilities). Light-only; tokens are contrast-tested by `apps/web/src/app/theme.test.ts`.
- One copy table: `apps/web/src/content/site.ts` (`SiteName`, `SiteTheme`, `SitePath`, `SiteCopy`).
- Landmarks: skip link → header (`nav` "Primary") → `main#main-content` → footer. Targets ≥ 48 px; `:focus-visible` ring; safe-area padding with `viewport-fit=cover`.

## Tests

Every source file, including routes and layouts, is at 100% per-file coverage; `test:coverage` runs the manifest check after Vitest. `apps/web/src/app/AppRoutes.test.tsx` proves route wiring, metadata, landmarks, and error recovery.
