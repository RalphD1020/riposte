# Performance

> See also: [README.md](../../README.md)
> Source: architectural decision

Performance is architectural. The website server-renders, ships minimal JS, and uses the system font stack. The game must not run on the Next.js main thread.

## Website

- Server-side rendering
- Minimal JavaScript
- System font stack (no web font downloads)
- Static export supported (`pnpm build:static`)

## Game

- Godot Compatibility renderer for Web
- Single-threaded export (nothreads)
- Mobile VRAM compression enabled
- Desktop VRAM compression enabled

## Development

- Turbopack for fast Next.js dev
- Parallel workspace tasks via Turbo
- Incremental TypeScript compilation
