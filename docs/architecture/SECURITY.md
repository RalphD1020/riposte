# Security

> See also: [README.md](../../README.md)
> See also: [spec/invariants.md](../../spec/invariants.md)

## Secrets

Never commit:

- `.env` or `.env*.local`
- `*.pem`
- `**/.godot/export_credentials.cfg`

The security check (`pnpm security:check`) validates:

1. `.gitignore` contains required patterns
2. No tracked files contain private keys or AWS credentials
3. No tracked env files (except `.env.example`)

## Content Security Policy

The Next.js site sets strict CSP headers:

- No `unsafe-eval`
- `frame-ancestors 'none'`
- `object-src 'none'`

See `apps/web/next.config.ts` for the full policy.

## Trust Boundaries

- Browser is untrusted
- Next.js server renders public content only
- Godot game runs in browser sandbox
