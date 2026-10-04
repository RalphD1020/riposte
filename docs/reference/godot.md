# Godot Conventions

> See also: [README.md](../../README.md)
> See also: [docs/architecture/monorepo.md](../architecture/monorepo.md)
> Source: `game/project.godot`

## Version

Authoritative runtime: Godot **4.7.2-stable**

## Renderer

Compatibility (gl_compatibility) for Web. Do not use Forward+ or Mobile renderers.

## Warnings

Zero tolerance: no `@warning_ignore`. Default warnings are errors.

## Project Structure

```text
game/
├── project.godot          # Project configuration
├── export_presets.cfg     # Export configuration (committed)
├── src/                   # Production source
│   └── main/              # Application entry
├── tests/                 # Test suites
│   └── harness/           # Test harness
├── content/               # Game content
├── tools/                 # Editor tools
└── scripts/               # Build scripts (Node.js)
```

## Export

Web export uses single-threaded (nothreads) templates with mobile and desktop VRAM compression enabled.
