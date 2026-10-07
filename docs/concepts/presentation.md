# Presentation

> See also: [spec/invariants.md](../../spec/invariants.md) — PRES-001, PRES-KIT-001, HITSTOP-001, UX-001, COMBAT-009
> See also: [docs/concepts/ux.md](./ux.md), [docs/concepts/simulation.md](./simulation.md), [docs/concepts/combat.md](./combat.md)
> See also: [docs/reference/godot.md](../reference/godot.md) — the rig and animation contract for authored scenes
> Source: `game/src/presentation/`, `game/content/presentation/`

Presentation turns authoritative facts into pictures, sound, and feel. It never decides them (PRES-001).

## The combat presentation contract (COMBAT-009)

Presentation may **exaggerate** a normalized authoritative value; it may never **invent** one, and it may never feed anything back into the simulation. No presentation code recomputes a combat formula. If a quantity is not on `PresentationSnapshot` or an event payload, the trail and the audio do without it.

The snapshot carries what a swing means, so the renderer never has to re-derive it: `tip_speed`, `launch_readiness`, `swing_progress`, `swing_potential`, `commitment`, `stability`, `exposure`, `facing_error`, `stable_side`, `guard_region`, and `burst`. Final strike quality is deliberately absent — it only exists at contact, so it arrives on the `body_hit` payload with its `grade` already named.

Two consequences worth stating plainly:

- **Before contact, nothing predicts.** The interface shows the attacker's own potential and lets the target's vulnerability read from their own physical state — displaced weapon, committed swing, bad angle, carried momentum, recovery pose. Convergence is revealed only at contact, so the interface never lies.
- **Progress is travel.** Because `swing_progress` comes from physical travel rather than an animation clock, a blade stopped by another blade visibly stops. Authored animation follows the simulated sword geometry, not the reverse.

## Reading a swing from the primitives

The blade ribbon (`SwordTrail3D`) is the main combat read, and it is a reading rather than decoration. Each sample carries the `swing_potential` the simulation computed at that instant, and the ribbon's silhouette thickness and opacity come from it: thin while the swing is gathering, heaviest through the genuinely dangerous part of the arc, tapering as the swing spends itself. Because the potential is taken from the blade and not from the input that produced it, the heavy part lands in a slightly different place every swing — there is a living acceleration curve to learn, not a crit frame to memorize.

The blade's percussion band is drawn as a **separate, narrower rib floating just above the band**, so the sweet region reads as its own shape rather than as a tint. Colour may reinforce it; it never carries it alone. Its position comes from `SwingSemantics.SWEET_REGION_MIN/MAX`, so there is exactly one definition of where it is.

Wind-back needs no invented cue, because the blade physically travels backwards — the best anticipation the game has is already free. Audio only tightens behind it: one held voice per fighter whose pitch and level ride the wind-back actually earned. It plateaus at the top because `charge` saturates at the most that is physically reachable, not because of an authored cap. There is no charge glow.

Footwork writes on the floor and swings write in the air, so the two can never be confused at a glance. A burst kicks flat dust at ankle height, drifting _opposite_ the heading the simulation froze and carried on the `burst_started` payload.

A miss is information, not a non-event: the swing follows through into a readable recovery pose, and nothing punctuates it — no hitstop, no contact sound, no spark.

## Impact feedback comes from physical channels

Each feedback channel is driven by the physical quantity that actually causes it, and by nothing else:

| Channel                | Driven by                                                  |
| ---------------------- | ---------------------------------------------------------- |
| Hitstop                | clash `intensity`, or a strike's `quality`                 |
| Spark count and speed  | clash `intensity`                                          |
| Spark direction        | the carried contact `normal` and `strike` direction        |
| Recoil streak          | the carried `normal` scaled by the `push` actually applied |
| Camera impulse         | the same intensity or quality, along the same normal       |
| Contact audio category | the resolver's own contact class                           |
| Swing whoosh           | `swing_potential`, so weapon length and mass are in it     |

Hitstop is authored as three **bands** on the kit — `hitstop_blade` (0–40 ms), `hitstop_body` (25–65 ms), and `hitstop_devastating` (60–90 ms) — and interpolated by the physics. There is no value per class name, which is exactly why an awful heavy graze cannot feel stronger than a perfect tap riposte: quality is what the mapping reads. It remains wall-clock only; authoritative time never freezes (HITSTOP-001).

Contact geometry is **carried, not reconstructed**. `blade_collision` and `body_hit` payloads include the collision normal, the direction the striking point was travelling, and for a strike the velocity change the impulse imparted. Presentation previously rebuilt a normal by rotating the vector between the two fighters, which is a guess that can disagree with the impulse that was actually applied; now the sparks, the recoil, and the camera all lean the way the resolver says the blow went.

A bind is its own category rather than a quiet clash: it has its own sustained grinding sound and deliberately **no hitstop**, because the simulation has already stopped both blades dead and freezing on top of that reads as a hitch.

The camera reinforces boundaries only — nothing for an ordinary swing, barely anything for a clash, and even a devastating strike stays inside a restrained ceiling. This is a duel read in millimetres.

Victim reaction comes from the simulation first. The proxy stands exactly where the state says even on the frame it is struck; the flinch is animation, and there is no recoil overlay that could throw a target further than the impulse did.

Accessibility scales how loudly these cues are drawn and never what they mean. `trail_strength` may remove the ribbon entirely or thicken it; `sweet_spot_cue` may turn the rib off or exaggerate it. Neither moves the sweet region, changes damage, or changes timing. Both come from `PlayerSettings`, so `Off` is a supported way to play rather than a handicap: with shake, motion, the ribbon, and the rib all switched off, a hit is still marked in the world, still heard, still felt in the pacing (proven by PRES-PRESENTER).

`PlayerSettings` also provides continuous `screen_shake` (0.0–1.0), `flash_intensity`, `particle_intensity`, and a `combat_readability` mode (NORMAL / ENHANCED). Legacy `bool` screen_shake migrates on load (`true` → 1.0, `false` → 0.0). `reduced_motion` remains as a convenience preset that lowers motion-related settings together. None of these reach the simulation — a settings-hash-invariance test proves that different presentation settings produce identical authoritative hashes.

## Combat readability state

`PresentationFighter` carries normalized 0-1 readability scalars computed once per tick by `SnapshotProjector`. Raw quantities that are already 0-1 (charge, commitment, exposure, swing_progress, swing_potential, stability) are not duplicated; additional derived readings are:

| Field                  | Source                                  | Description                |
| ---------------------- | --------------------------------------- | -------------------------- |
| `recovery_remaining01` | recovery_left / recovery_ticks          | 1 = just started, 0 = done |
| `stamina01`            | stamina / stamina_max                   | 0 = empty, 1 = full        |
| `point_threat01`       | Tip axial closing (PHYS-007 kinematics) | 0 = safe, 1 = lethal line  |
| `movement_speed01`     | speed / max_speed                       | 0 = still, 1 = sprinting   |
| `burst01`              | Gesture burst kind                      | 0 or 1 (burst in progress) |

`ImpactFeedback` (`game/src/presentation/snapshot/impact_feedback.gd`) is a typed read-only projection of contact event payloads, so presentation never reaches into raw dictionaries. It carries normalized impulse/severity, contact geometry, and attacker/target slots.

`DebugVectors3D` draws the quantities themselves — body velocity, the tip's actual direction of travel, and the percussion band — as world-space lines from snapshot values, next to the numbers in the text overlay. One F3 shows both, because a closing speed you cannot see the direction of is half a reading.

## Data flow (PRES-002)

```text
MatchState ──SnapshotProjector (once per tick)──▶ PresentationSnapshot ─┐
DuelEvents (that tick) ─────────────────────────────────────────────────┤
                                                                        ▼
CombatFeedbackDirector.process(snapshot, events, settings)
    → FeedbackFrame { camera[], fighter[], weapon[], audio[], vfx[], hitstop[] }
        ↓
CameraFeedback.apply(camera_requests, delta) → camera offset
FighterPresenter.apply(fighter_requests)      → body pose
WeaponPresenter.apply(weapon_requests)        → blade visual
AudioPresenter.apply(audio_requests)          → SFX bus
VfxPresenter.apply(vfx_requests)              → particle bursts
PresentationTimeController.apply(hitstop_requests) → FixedTickDriver.hold()

MatchPresenter.render(alpha, delta) → interpolate last two snapshots → pose passive proxies → camera
DuelHud.update(snapshot)            → health, pips, round, low-time clock, banner (writes only on change)
```

`MatchScreen` (application) owns the loop; presentation emits only requests and intents (`hitstop_requested`, `pause_pressed`, touch `move_changed` / `attack_*`). See [docs/architecture/presentation-feedback.md](../architecture/presentation-feedback.md) for the full architecture.

## Change art, animation, or sound in one place (PRES-KIT-001)

Each combatant identity has a `CombatantPresentationKit` composing a `FighterPresentationKit` and a `WeaponPresentationKit` (`game/src/presentation/kit/`). This split exists because the same fighter may hold different weapons and different fighters may hold the same weapon.

To replace the primitive look of an identity (e.g. a Blender model):

1. Import the `.glb` and wrap it in a scene (optional `AnimationPlayer` with clips).
2. Author a kit `.tres` at the identity's path in `RiposteKits.AUTHORED_KIT_PATHS` (`game/content/presentation/riposte_kits.gd`) with the scene, animation clips (semantic → clip), and audio cues filled in.
3. Nothing else changes. Authored kits load first; the factory primitive kit fills any gap. Debug builds fail closed on a missing kit; release builds use a placeholder.

Generic presentation code never names an identity (lint bans it); kits are resolved once per match (`DuelKits.resolve`).

The authoritative weapon angle drives the blade visual. Character animation visually supports the sword position, never the reverse. See [docs/architecture/presentation-feedback.md](../architecture/presentation-feedback.md) for the full architecture.

## Components

| Component                                                                                                 | Code                                                                         |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Theme (palette, sizes, fonts, styleboxes, container defaults, type variations) — the game's `globals.css` | `game/src/presentation/theme/riposte_theme.gd`                               |
| Audio buses (Master → Music, SFX), loaded by the engine before anything plays                             | `game/default_bus_layout.tres`, `game/src/presentation/audio/audio_buses.gd` |
| Kits, catalog, per-match kit set                                                                          | `game/src/presentation/kit/`                                                 |
| MVP-0 kits, camera profile, procedural audio                                                              | `game/content/presentation/`                                                 |
| Snapshot + projector (the only read boundary)                                                             | `game/src/presentation/snapshot/`                                            |
| Arena axes: world = (x, 0, −y), yaw = θ + π/2                                                             | `game/src/presentation/spatial/arena_transform.gd`                           |
| Passive fighter proxy (primitive or authored; x-ray blade) and sword trail                                | `game/src/presentation/entities/`                                            |
| Arena scaffold (floor to `platform_radius`, warning ring at `warning_ring_radius`, edge strip, lights)    | `game/src/presentation/world/arena_scaffold.gd`                              |
| Duel camera (fixed orientation, smooth zoom, tiny impulses)                                               | `game/src/presentation/camera/`                                              |
| VFX (capped), audio (pooled voices; SFX + Music buses), haptics                                           | `game/src/presentation/vfx/`, `audio/`, `feedback/`                          |
| Coordinator                                                                                               | `game/src/presentation/match/match_presenter.gd`                             |
| HUD, pips, icons, debug overlay, debug vectors, HUD copy                                                  | `game/src/presentation/hud/`                                                 |
| Touch controls (floating joystick + attack zone)                                                          | `game/src/presentation/input/touch_controls.gd`                              |

## Rules of thumb

- Proxies are passive: only `MatchPresenter.render` poses them.
- Feedback scales with physics (contact class, damage) and honors `PresentationOptions` (reduced motion disables camera impulses; reduced flash dims effects; hitstop still conveys impact). Per-identity feel (hitstop, trails) lives in kits; generic feedback constants (spark counts, ring sizes, swing mix, impulse ceilings, audio tiers) live on `CombatFeedbackDirector` and are referenced by `MatchPresenter`. VFX-specific constants (sizes, lifetimes, spreads) live on `VfxDirector`.
- Styling goes through `RiposteTheme`: components pick a `theme_type_variation` (`HudPlate`, `HudStack`, `HudRow`, `HudTitleLabel`, `HudAccentLabel`, `PlayerHealthBar`, …). The only per-node style is runtime safe-area margins (`RiposteTheme.apply_insets`).
- Blades render without depth test so the sword is always readable (combat-critical information).
- Icons are drawn shapes (`HudIcons`, `PipRow`), never glyphs the shipped font lacks.
- Audio: kit cues on the SFX bus; the arena kit's `music` cue loops on the Music bus while a duel is mounted.
