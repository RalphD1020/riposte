# Security

> See also: [README.md](../../README.md), [spec/invariants.md](../../spec/invariants.md) — WEB-005, WEB-006, CMD-001
> Source: `apps/web/next.config.ts`, `apps/web/src/config/runtimeConfig.ts`, `scripts/check-security.mjs`

## Secrets

Never commit:

- `.env` or `.env*.local` (only `.env.example` is tracked)
- `*.pem`
- `**/.godot/export_credentials.cfg`

`pnpm security:check` validates `.gitignore` patterns, rejects tracked private keys / AWS credentials, and rejects tracked env files other than `.env.example`.

## Website headers (server mode)

Strict CSP (no `unsafe-eval`, `frame-src 'none'`, `frame-ancestors 'none'`, `object-src 'none'`, `form-action 'self'`, `base-uri 'self'`), `X-Frame-Options: DENY`, `nosniff`, HSTS, strict referrer policy, and a Permissions-Policy denying camera, microphone, and geolocation. Static hosts must set equivalent headers themselves.

## Untrusted input

- **Environment destinations** are validated before use (WEB-006): public URLs https only; local play loopback http or same-origin paths; protocol-relative, `javascript:`, and malformed values become unconfigured.
- **Host header** only selects between the local export and the public page; spoofing it can only redirect the spoofer to their own loopback.
- **Error UI** never renders raw error messages.
- **Commands** are sanitized by the simulation (CMD-001); **settings files** are sanitized on load and failures fall back to defaults.
- **Community links** in the game open only `https://` URLs.

## Trust boundaries

- The browser and every client are untrusted. MVP-0 results are local and unverified; trusted outcomes (ranked, ELO) require server re-simulation of commands with hash comparison (`ReplayVerifier`).
- The Next.js server renders public content only. The game runs in the browser sandbox and talks to no backend.
