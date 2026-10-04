# Local Development

> See also: [README.md](../../README.md)
> See also: [docs/reference/tooling.md](../reference/tooling.md)

## Prerequisites

- Node.js 20.9+
- pnpm 10.x
- Godot 4.7.2-stable (on PATH or `GODOT_BIN` env var)

## Setup

```bash
pnpm install
```

## Development

```bash
# Start both Next.js and Godot Web serve
pnpm dev

# Or start individually
pnpm dev:web              # Next.js on :3000
pnpm --filter @riposte/game dev  # Godot Web on :8060
```

## Validation

```bash
pnpm check   # Full validation (import + lint + typecheck + docs/arch)
pnpm test    # Run all tests
pnpm verify  # check + test + build
```

## Cleanup

```bash
pnpm clean     # Remove generated files (keep node_modules)
pnpm reinstall # Full clean + install
pnpm kill      # Kill leftover dev servers
```

## Ports

- `:3000` - Next.js dev server
- `:3001` - Next.js fallback
- `:8060` - Godot Web serve
