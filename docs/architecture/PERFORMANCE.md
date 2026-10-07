# Performance

> See also: [README.md](../../README.md), [docs/concepts/presentation.md](../concepts/presentation.md)
> Source: `apps/web/next.config.ts`, `game/src/application/app/ui_scale.gd`, `game/src/presentation/`

Performance is architectural and mobile-first. Priority: reliability → security → performance → UX → cost.

## Acceptance targets

Agreed before measuring, so a result has a verdict instead of an argument. The
device and browser floor they are measured against, and the procedure, are in
[docs/reference/device-qa.md](../reference/device-qa.md#sustained-performance).

| What                           | Target                                  |
| ------------------------------ | --------------------------------------- |
| Simulation rate                | 60 Hz, unconditionally                  |
| Tick backlog                   | Never sustained at `MAX_CATCH_UP_TICKS` |
| Render, combat, minimum device | ≥ 30 fps sustained through a full round |
| Render, reference desktop      | 60 fps sustained                        |
| Drift across a full match      | None                                    |

Frame rate and tick rate are separate promises. The simulation is fixed-step
and authoritative, so a phone rendering at 34 fps plays the same duel as a
desktop at 60. A device that cannot keep up with 60 Hz of _simulation_ is a
different and worse problem: it starts spending catch-up ticks, which is a
correctness failure wearing a performance costume.

## Website

- Every route prerenders as static content; the layout reads no request data, so pages are CDN-cacheable and static-exportable.
- Client JavaScript is limited to `PlayGateway` (`/play`); everything else is Server Components.
- System font stack (no web font downloads); one stylesheet; SVG favicon.

## Game

- **Simulation**: scalar math, no allocations in the collision hot path (preallocated frames and reports), fixed 60 Hz with at most `MAX_CATCH_UP_TICKS` per frame; backgrounded tabs never fast-forward.
- **Physics**: semi-implicit Euler integration, selective CCD for blades, TOI-ordered chronological contact loop with bounded iterations. Mass-aware body collisions use inverse-mass impulse. Point-strike detection shares the same substep sweep as blade contacts. All contact geometry is integer-compatible (`SimMath`) scalars on the gameplay plane — no Godot `PhysicsServer3D` or `NavigationServer3D`.
- **Stamina**: motor work accounting (`P = τ·ω` rotational, `P = F·v` linear) normalizes against `PhysicalBaseline` reference values per channel. One effort signal feeds drain/recovery. Contact shock rides on existing hit events. All stamina arithmetic is in `StaminaModel` static functions with no allocation.
- **Capability**: `CapabilityModel` resolves a `[floor, 1]` scalar from health and stamina — four static calls (weapon, movement, turn, burst) per tick, each a clamp over two penalty curves. No allocation, no state.
- **Projection once per tick**: `SnapshotProjector` copies state once; frames only interpolate.
- **HUD** writes a `Label` or bar only when its value changes.
- **Effects**: live VFX are capped (`MAX_EFFECTS`) and share one mesh and material per kind; audio voices are pooled (spatial + flat + one music voice); trails draw one `ImmediateMesh` from a bounded sample ring.
- **A switched-off cue costs nothing.** `SwordTrail3D` and `DebugVectors3D` check `get_surface_count()` before clearing, so the off state — which is the default for debug vectors and the Reduced Motion setting for trails — is not an empty mesh cleared again 60 times a second. Trail samples still accumulate and age while off, so turning a cue back on is immediate.
- **Rendering**: Compatibility renderer, primitive meshes, a handful of lights; 3D renders at ≤ 2× CSS resolution (`UiScale.scale_3d_for`) so dense phone panels do not multiply fill cost.
- **Startup**: procedural placeholder audio is generated once and cached (low-rate music bed); kits resolve once per match.
- **Web export**: single-threaded (no COOP/COEP requirement), desktop + mobile VRAM compression.

## Development

- Turbopack for Next.js dev; Turbo runs workspace tasks in parallel; incremental TypeScript.
