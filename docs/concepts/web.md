# Web

> See also: [README.md](../../README.md), [docs/architecture/monorepo.md](../architecture/monorepo.md)
> See also: [spec/invariants.md](../../spec/invariants.md) — WEB-004, WEB-005, WEB-006, UX-001
> Source: `apps/web/`

`@riposte/web` is the Next.js App Router gateway: what Riposte is, how to play, community destinations, and the Play button. It never hosts or initializes the Godot runtime (MONO-001).

## Routes

| Route                            | View                                                       | Notes                                                              |
| -------------------------------- | ---------------------------------------------------------- | ------------------------------------------------------------------ |
| `/`                              | `HomePage`                                                 | One primary action (Play Riposte), how to play, community stubs    |
| `/play`                          | staged Godot export, else `PlayPage` → `PlayGateway`       | Play admission (WEB-005)                                           |
| `/how-to-play`                   | `HowToPlayPage`                                            | Mirrors the in-game How to Play (copy kept in sync with `AppCopy`) |
| `/about`                         | `AboutPage`                                                | What this release is                                               |
| not found / error / global error | `not-found.tsx`, `error.tsx` (`retry`), `global-error.tsx` | Plain language; never the raw error message                        |

Every route prerenders as static content; the layout reads no request data.

## Play admission (WEB-005)

The game is served from this origin. Every Play CTA is a plain link to `/play`, and `resolvePlaySurface(config)` (`apps/web/src/config/runtimeConfig.ts`) picks the first surface that exists:

| Surface       | Destination                                                                          |
| ------------- | ------------------------------------------------------------------------------------ |
| `hosted`      | `/game/index.html` — the Godot Web export staged into `apps/web/public/game/`        |
| `itch`        | `NEXT_PUBLIC_PLAY_URL` (https only), the published itch.io build                     |
| `local`       | `NEXT_PUBLIC_LOCAL_PLAY_URL`, default `http://127.0.0.1:8060/`, the pre-publish loop |
| `unpublished` | the "not published yet" page; never an invented URL                                  |

Hostname does not appear. It used to: `/play` was a redirect, so the site had to guess which build a visitor could reach from where they were standing. Now whether the game is here is a fact about the deployment, established at build time by the staging step, and the same resolution runs in both build modes.

- Server builds rewrite `/play` → `/game/index.html`, but **only when the artifact is staged**. An unconditional rewrite would turn an unstaged `/play` into a 404 instead of the page that explains where the game is.
- Static exports have no rewrites, so `PlayGateway` performs the hop in the browser with a visible fallback link. When the resolved surface is `itch` the page says the hop leaves this site — arriving on another domain unannounced is the one thing this page can do that looks like a bug. `PlayView` reads `admission.surface`, not the shape of the href: whether a destination is off-site is the admission decision's own answer, and re-deriving it from a leading slash would be a second, quieter copy of it.

itch.io is a secondary home rather than the front door: it appears beside Discord and Patreon as "Also on itch.io".

## Hosting the export (WEB-004)

`pnpm game:export:web` writes the canonical artifact to `dist/game/web/` — still the itch upload. `pnpm game:stage:web` then **copies** it into `apps/web/public/game/`, which is gitignored build output. Copy rather than move, so the itch artifact is untouched, and the destination is replaced wholesale rather than merged over: a stale `index.pck` beside a fresh `index.wasm` is a crash with no useful message. Staging verifies `index.html`, `index.js`, `index.wasm`, and `index.pck` before copying anything, because a `/play` that loads a shell and then 404s on the wasm looks like a working deploy.

MONO-001 still holds. Next serves these bytes and never owns them; `.gd`, `.tscn`, `.tres`, and `project.godot` live only in `game/`, and `scripts/check-architecture.mjs` enforces that.

`next.config.ts` grants the engine what it needs **path-scoped to `/game/:path*`**: `script-src 'wasm-unsafe-eval'` for WebAssembly and `worker-src 'self' blob:` for the audio worklet. Widening the site-wide policy to cover one directory would hand those capabilities to every page that does not need them. The export is single-threaded Compatibility (`thread_support=false`), so there is no `SharedArrayBuffer` and therefore no COOP/COEP requirement — which is why it can sit on our own origin beside ordinary pages. `frame-src 'none'` and `X-Frame-Options: DENY` hold everywhere; nothing is iframed.

Both policies are built from one `sharedCspDirectives` list, so the two differ **only** in what the engine needs and hardening the site can never silently skip `/game`. `runtimeConfig.test.ts` imports the config and reads the computed headers rather than scanning the source text: it asserts the engine capabilities appear under `/game/:path*` and nowhere else, and that every shared protection appears in both. Asserting on source text would pass while the shared block handed `wasm-unsafe-eval` to every page.

The engine files are not content-hashed, so `/game/index.html` is `no-cache` and the payload is `must-revalidate`. A cached shell beside a new `.pck` is the failure this prevents.

## Configuration

`runtimeConfig.ts` is the only module that reads `process.env.NEXT_PUBLIC_*` (each by literal name, so Next inlines it). Values are validated (WEB-006): public URLs https only; local play may be loopback http or a same-origin path; `/play` itself and anything else is unconfigured. See `apps/web/.env.example`.

| Variable                                                | Use                                             |
| ------------------------------------------------------- | ----------------------------------------------- |
| `NEXT_PUBLIC_PLAY_URL`                                  | Public itch page (empty until published)        |
| `NEXT_PUBLIC_LOCAL_PLAY_URL`                            | Local game override                             |
| `NEXT_PUBLIC_COMMUNITY_URL` / `NEXT_PUBLIC_SUPPORT_URL` | Discord / Patreon; empty renders "Coming soon"  |
| `NEXT_PUBLIC_APP_VERSION`                               | Set by `next.config.ts` from `package.json`     |
| `NEXT_PUBLIC_HOSTED_PLAY`                               | Set by `next.config.ts` when `/game/` is staged |

## Styles and copy

- One stylesheet: `apps/web/src/app/globals.css` (`@theme` tokens + semantic classes; JSX never uses utilities). Light-only; tokens are contrast-tested by `apps/web/src/app/theme.test.ts`, which also gates the two hand-authored files no bundler reads — `public/site.webmanifest` and `public/favicon.svg` must carry the same `SiteTheme` colors, because on a phone `theme_color` paints the browser chrome and `background_color` is the whole screen while an installed app starts.
- One copy table: `apps/web/src/content/site.ts` (`SiteName`, `SiteTheme`, `SitePath`, `SiteCopy`).
- Landmarks: skip link → header (`nav` "Primary") → `main#main-content` → footer. Targets ≥ 48 px; `:focus-visible` ring; safe-area padding with `viewport-fit=cover`.

## Tests

Every source file, including routes and layouts, is at 100% per-file coverage; `test:coverage` runs the manifest check after Vitest. `apps/web/src/app/AppRoutes.test.tsx` proves route wiring, metadata, landmarks, and error recovery.
