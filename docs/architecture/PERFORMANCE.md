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

A fast blade is not a reason to raise the tick rate. A sword point moving
15–25 m/s covers 25–40 cm in a tick, and that is exactly what the bounded
swept collision exists for: substeps sized by blade and carriage travel inside
one 60 Hz tick, with the contacts resolved in time order. Raising the whole
simulation rate would multiply every system's cost on a phone to buy what the
sword sweep already provides. Only a measured tunnelling or contact-ordering
failure the sweep cannot fix reopens that.

## Website

- Every route prerenders as static content; the layout reads no request data, so pages are CDN-cacheable and static-exportable.
- Client JavaScript is limited to `PlayGateway` (`/play`); everything else is Server Components.
- System font stack (no web font downloads); one stylesheet; SVG favicon.

## Game

- **Simulation**: scalar math, no allocations in the collision hot path (preallocated frames and reports), fixed 60 Hz with at most `MAX_CATCH_UP_TICKS` per frame; backgrounded tabs never fast-forward.
- **Physics**: semi-implicit Euler integration, selective CCD for blades, TOI-ordered chronological contact loop with bounded iterations. Every contact cap is fixed — CCD substeps, contacts per tick, contact-set points (`SwordContactSet.CAPACITY` = 6, two on each of the three steel pairs, preallocated), contact-block pivots (`ContactLcp.MAX_PIVOTS`), solver iterations (a constant, never "until converged") — so a pathological frame costs what an ordinary one does; reaching a cap is counted, never extended (CONTACT-MANIFOLD-001). The counters and the wall-clock cost of one step are Godot custom monitors (`Riposte/CcdCapHits`, `Riposte/ContactCapHits`, `Riposte/MaxManifoldPoints`, `Riposte/ReholdBudgetExhausted`, `Riposte/PositionGuardHits`, `Riposte/MeaningfulContactsDropped`, `Riposte/PivotCapHits`, `Riposte/SimStepUs`), one per cap and never summed, readable in the editor debugger and in exported builds. A healthy representative match reads zero on every cap counter; that is a release gate on exported builds, not a target to reach by raising budgets. Contact physics is not simplified for CPU fear: two fighters and a handful of scalar constraints are tiny next to skinning and rendering — measure release builds first. Mass-aware body collisions use inverse-mass impulse. Point-strike detection shares the same substep sweep as blade contacts. All contact geometry is integer-compatible (`SimMath`) scalars on the gameplay plane — no Godot `PhysicsServer3D` or `NavigationServer3D`.
- **Condition**: `ConditionModel` writes each fighter's three scales into a reused `ConditionState` in its tick scratch once per tick — three linear maps of the health fraction. No allocation, no state.
- **Threat estimate**: `InitiativeModel.threat_time` is a fixed 30-tick rollout (one pose and one capsule test per tick, no allocation in the loop); it runs only where a reading is needed (contact classification, exposure, CPU observation, snapshot).
- **Projection once per tick**: `SnapshotProjector` copies state once; frames only interpolate.
- **HUD** writes a `Label` or bar only when its value changes; the round-start card and chrome policy change only on a phase transition. The crowd bed trim writes `volume_db` only when the change passes hysteresis (`MatchPresenter._ride_crowd_bed`).
- **Fighter pose: one clip layer, one combat-pose pass, one native IK.** Per fighter the runtime stack is the `AnimationPlayer` (in-place locomotion, breathing, terminal clips; normal process step, presentation time as `speed_scale`, no root motion), one `CombatPoseModifier3D` (torso support and the elbows' bend planes, bone indices cached, nothing allocated per frame), and one `TwoBoneIK3D` with both arms as two settings. The orbit sample, lift, cut curve, elbow guides, and clearance are pure math and data (`WeaponKinematics`, `CombatPresentationField`, `CutPresentationCurve`, `ElbowGuideField`, `PoseClearance`) — never extra modifiers, never physics bodies or shape queries. Self-penetration is prevented **offline**: PRES-RIG sweeps the whole pose domain (5° steps × phases × charge levels × both sides) against the profile's proxies, and the runtime does no clearance correction at all. Do not add `AnimationTree` until locomotion genuinely needs continuous blending; do not thread or move this to GDExtension unless device profiling shows the pose pass above ~0.5 ms for both fighters.
- **Hidden actors don't animate.** The intro's showcase figures are freed when it ends, the match presenter is gone before the victory showcase, and the showcase is freed on leaving the results.
- **Effects**: live VFX are capped (`MAX_EFFECTS`), reuse a fixed pool of nodes (no allocate/free in sustained combat), and share one mesh and material per kind; audio voices are pooled (spatial + flat + one music voice; that player processes only while a handoff is pending); trails draw one `ImmediateMesh` from a bounded sample ring.
- **A switched-off cue costs nothing.** `SwordTrail3D` and `DebugVectors3D` check `get_surface_count()` before clearing, so the off state — which is the default for debug vectors and the Reduced Motion setting for trails — is not an empty mesh cleared again 60 times a second. Trail samples still accumulate and age while off, so turning a cue back on is immediate. `FacePresentation` indexes the eye nodes once at proxy build and skips the visibility write while `terminal_cause` is unchanged (`game/src/presentation/entities/face_presentation.gd`).
- **Rendering**: Compatibility renderer, primitive meshes, a handful of lights; 3D renders at ≤ 2× CSS resolution (`UiScale.scale_3d_for`) so dense phone panels do not multiply fill cost.
- **Startup**: procedural placeholder audio is generated once and cached (low-rate music bed); kits resolve once per match.
- **Web export**: single-threaded (no COOP/COEP requirement), desktop + mobile VRAM compression.

### Mobile budgets and renderers

Engineering targets at 60 FPS (16.67 ms), to be measured on real devices — not Godot guarantees:

| System                                               | Target                          |
| ---------------------------------------------------- | ------------------------------- |
| Both fighters' combat-pose passes                    | < 0.5 ms CPU                    |
| Skeleton animation and skinning prep                 | < 1.5 ms CPU                    |
| All combat presentation scripting                    | < 1.0 ms CPU                    |
| Fighters + weapons + trails                          | < 2 ms GPU                      |
| Ordinary combat VFX                                  | < 1.5 ms GPU                    |
| Normal match frame (≈20–25% headroom)                | < 12–13 ms                      |
| Full authoritative tick, both CPU decisions included | p99 ≤ 8.3 ms                    |
| Frame deadline                                       | no sustained misses of 16.67 ms |

The last two rows are a working target for the release profile that is still owed. The debug numbers below were taken on the editor binary. They are a different build, and they are not that measurement. The minimum supported Windows machine is not decided. The i7-8700K readings are this desk, not that decision.

### Measured

Desktop readings (i7-8700K, RTX 2080, rules v49) — upper bounds for script cost, not device numbers. Native rows are `tools/perf_report.gd` over four Hard-vs-Hard matches (15,681 ticks) on the headless editor binary, a debug build with no GPU; the frame row is start-to-start with the frame limiter and the headless idle sleep off, because Godot's process-time monitor reports the worst frame of each second rather than the current one. "Push" includes building the tick's `PresentationSnapshot`.

| Per 60 Hz frame                          | mean    | p99     |
| ---------------------------------------- | ------- | ------- |
| Authoritative step                       | 0.95 ms | 4.7 ms  |
| … with swords held in contact            | 2.25 ms | 7.1 ms  |
| … with swords apart                      | 0.75 ms | 2.8 ms  |
| Both CPU controllers                     | 0.38 ms | 2.8 ms  |
| Presentation scripting (push + render)   | 0.54 ms | 1.13 ms |
| Whole frame, presented                   | 2.08 ms | 6.7 ms  |
| Whole frame, no presenter (engine floor) | 1.23 ms | 5.5 ms  |

Rules 51 and 52 on the same tool (four Hard-vs-Hard matches, about 10,500 ticks; mean / p99 / max):

| Per 60 Hz frame      | rules 51             | rules 52              |
| -------------------- | -------------------- | --------------------- |
| Authoritative step   | 0.64 / 3.3 / 12.4 ms | 0.74 / 3.7 / 9.8 ms   |
| Both CPU controllers | 0.45 / 6.6 / 26.5 ms | 0.79 / 18.1 / 68.6 ms |
| Whole frame          | 1.83 / 9.1 / 49.1 ms | 2.23 / 20.9 / 70.9 ms |

The worst debug frames — rules 51's 48 ms and rules 52's 70 ms — are CPU decision ticks, not the simulation: a decision runs several 30-tick threat predictions, and since rules 51 every predictor tick whose blades come within that tick's travel is swept at `STEEL_SWEEP_SAMPLES` instants, each a full steel measure; rules 52's measure is three steel pairs, and its travel bound now includes each crossguard's ends. The median CPU cost is small (32 µs); the tail is that sweep. Attributed on 896 route estimates from Hard–Medium ladder states (debug build; mean / p99 per estimate): shipped 6.5 / 29.3 ms; without the in-tick sweep 1.6 / 4.6 ms; without guard roots 4.3 / 18.7 ms; without both 1.3 / 3.7 ms — the sweep is about four times the cost, the guard roots about half again on each of its samples.

No predictor optimization is made from these debug numbers. The release measurement is still owed, and this machine cannot take it: only the web export templates are installed, and the web build has no way to run the deterministic CPU corpus. To take it: install the 4.7.2 desktop release template; export a local (uncommitted) desktop preset that includes `tools/perf_report.gd`; run that release binary headless with `--script res://tools/perf_report.gd` on the same four Hard-vs-Hard matches, without a profiler attached; record p50, p95, p99, maximum and the frames over 16.7 ms. Only if those miss the frame target is a cheaper steel query worth prototyping — a boolean "does any steel touch?" that keeps the same swept interval, candidates and ownership policy exactly and only stops work once the answer is known — and only kept after it is shown equal on boundary, mirrored, near-parallel and fast-rotation scenes and on the CPU corpus, with predictor agreement and replay determinism rerun. Not yet optimized, and no budget is set from these debug numbers: the release Web build is measured first, and the candidates are a clearance-only measure for the predictor (it needs the least gap, not a manifold) or a coarser sweep refined only where the steel closes.

Presentation scripting is inside its 1 ms budget on average and at its edge at p99. It had drifted to 3.7 ms by rules 47 without anyone noticing: the snapshot projected each fighter's exposure and threat time — six 30-tick threat predictions a tick (two distinct), which the swept-blade estimator (rules 43) and the hand discs (rules 48) made far dearer — for readings only the debug overlay displays. They are now two predictions, taken only while the overlay is shown (`SnapshotProjector.project(..., threat_readings)`). The authoritative step's tail during held blade contact is the largest single cost, and it is the first thing to measure on a phone: interpreted GDScript in WebAssembly on a mid-range handset is several times slower than this desktop. The collision sweep's hand checks are bounded per substep (a midpoint bound before the exact distances, bit-identical); it was 0.51 → 0.40 ms of the step on the profile corpus. Re-measured after the re-hold crossing refinement and the contact readings (`ContactOutcome`: one bounded, footwork-free threat estimate on an attack's first blade contact): the step reads about 9 % dearer on a corpus whose duels now take different paths, and presentation — unchanged code — about 10 %, so most of the difference is run-to-run noise; the engine-floor row was not re-taken. After the review-15 CPU work (current self-state, the steel-aware route readings of the capitalize intent — full-sword sweeps at decision ticks only, for an open opponent) the CPU controllers read about 0.49 ms mean and 5.1 ms p99 (from 0.38 / 2.8): the readings land on decision ticks, so the cost is spiky rather than steady. Inside the frame budget on desktop; the first thing to measure on a phone alongside the held-contact step.

The release Web export, run from `/play` in Cursor's embedded Chromium pane (ANGLE / Direct3D 11), holds a clean 60 fps on the menu and averages ~48 fps in a match, with about a quarter of frames taking two vsyncs. A sampling profile puts our WebAssembly at a few percent; ~57% of the time is the engine's two once-per-frame WebGL queries (`FRAMEBUFFER_BINDING`, `SCISSOR_TEST`), which are synchronous round trips that wait for the GPU process to finish the frame — about 95 draw calls and 2,300 WebGL calls per frame. That pane shares its GPU process with the IDE, so the reading is not representative of a standalone browser; if a standalone desktop browser or a phone shows the same, the lever is draw count, not the simulation. Only about 24 of the 95 draws are the duel itself (each fighter and each sword is one mesh with six material surfaces); the rest — arena kit, HUD, effects — are not yet attributed.

Rendering scenarios are `tools/perf_scenes.gd`: the shipping `MatchPresenter` on a real `DuelSimulation`, drawn by the Compatibility renderer into a fixed viewport, warmed up and repeated, recording frame wall time, the viewport's measured CPU and GPU render time, draw calls and primitives for an idle arena with and without the crowd, the key shadow off, movement, combat stress and a full match (windowed, never headless — the dummy renderer has no GPU). Desktop debug readings at 1280×720 with the 1024 hard-filtered key shadow, sword casting (rules 60): GPU render 2.0–2.4 ms median and at most 2.7 ms p95 in every scenario; 329–410 draw calls and about 315,000–332,000 primitives. Turning the key shadow off drops an idle arena to 209 draws and about 166,000 primitives, because `arena_bowl.glb` (about 159,000 triangles, roughly 95% of the scene) casts and is drawn a second time into the shadow map; the crowd adds 28 draws and about 14,000 primitives, and the two fighters are about 4,000 triangles. GPU time barely moves on this desktop, so nothing is optimized from it. Draw count and the bowl's shadow pass are the first things to measure on the lowest-target phone and in a standalone browser; if they miss the frame there, the candidate is letting only the wall course that shades the sand cast, not a lower atlas or a new rendering path.

Gameplay presentation MUST work on Mobile and Compatibility; Forward+ features are optional. Web is Compatibility (WEB-001). Native Android/iOS should target the Mobile renderer once native export presets exist (today `rendering_method.mobile` is still `gl_compatibility`, because only the web export ships). Live combat stays lean: one key light plus emissive accents (no light per clash), one short trail per sword from a fixed sample ring (`trail_samples` = 10), pooled VFX nodes under a hard cap, low-poly rigid block bodies with no morph targets and a minimal skeleton. Terminal, intro, and victory presentation may be richer, because only one of them runs at a time. Profile real matches — neutral spacing, held charge, rapid taps, binds, heavy VFX, dash thrust, ring-out, stab finisher, intro, victory — on the device matrix (native Android/iOS, Android and iPhone browsers, desktop Chromium, desktop native). Profile representative **release** builds (Godot 4.7's Android export templates can record Perfetto traces); debug and editor timings are not representative.

## Development

- Turbopack for Next.js dev; Turbo runs workspace tasks in parallel; incremental TypeScript.
