# Performance

> See also: [README.md](../../README.md), [docs/concepts/presentation.md](../concepts/presentation.md)
> Source: `apps/web/next.config.ts`, `game/src/application/app/ui_scale.gd`, `game/src/presentation/`

Performance is architectural and mobile-first. Priority: reliability → security → performance → UX → cost.

## Website

- Every route prerenders as static content; the layout reads no request data, so pages are CDN-cacheable and static-exportable.
- Client JavaScript is limited to `PlayGateway` (`/play`); everything else is Server Components.
- System font stack (no web font downloads); one stylesheet; SVG favicon.

## Game

- **Simulation**: scalar math, no allocations in the collision hot path (preallocated frames and reports), fixed 60 Hz with at most `MAX_CATCH_UP_TICKS` per frame; backgrounded tabs never fast-forward.
- **Projection once per tick**: `SnapshotProjector` copies state once; frames only interpolate.
- **HUD** writes a `Label` or bar only when its value changes.
- **Effects**: live VFX are capped (`MAX_EFFECTS`) and share one mesh and material per kind; audio voices are pooled (spatial + flat + one music voice); trails draw one `ImmediateMesh` from a bounded sample ring.
- **Rendering**: Compatibility renderer, primitive meshes, a handful of lights; 3D renders at ≤ 2× CSS resolution (`UiScale.scale_3d_for`) so dense phone panels do not multiply fill cost.
- **Startup**: procedural placeholder audio is generated once and cached (low-rate music bed); kits resolve once per match.
- **Web export**: single-threaded (no COOP/COEP requirement), desktop + mobile VRAM compression.

## Development

- Turbopack for Next.js dev; Turbo runs workspace tasks in parallel; incremental TypeScript.
