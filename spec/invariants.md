# Invariants

> Source: architectural constraints

Normative contracts for the Riposte project.

## Monorepo (MONO)

### MONO-001

`apps/web` and `game` are siblings. Next.js must not own the Godot runtime.

### MONO-002

Never add a no-op package script merely to satisfy Turbo.

### MONO-003

Root pnpm/Turbo owns orchestration. Do not hardcode package names in root scripts.

## Documentation (DOC)

### DOC-001

Authority: spec > code > docs

Code that violates spec is defective. Docs that contradict code are stale.

## Coverage (COVERAGE)

### COVERAGE-001

100% line/function/branch/statement coverage on measured packages.

## Web (WEB)

### WEB-001

Use Compatibility renderer for Web.

### WEB-002

No C#/Mono artifacts.

### WEB-003

Export uses single-threaded templates with VRAM compression.

### WEB-004

itch.io hosts the Godot Web export, not the Next.js app.

## Git (GIT)

### GIT-001

Agents must not create commits unless explicitly instructed.
