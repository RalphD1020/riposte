# Presentation

> See also: [spec/invariants.md](../../spec/invariants.md) — PRES-001, PRES-KIT-001, HITSTOP-001, UX-001
> See also: [docs/concepts/ux.md](./ux.md), [docs/concepts/simulation.md](./simulation.md)
> Source: `game/src/presentation/`, `game/content/presentation/`

Presentation turns authoritative facts into pictures, sound, and feel. It never decides them (PRES-001).

## Data flow

```text
MatchState ──SnapshotProjector (once per tick)──▶ PresentationSnapshot ─┐
DuelEvents (that tick) ─────────────────────────────────────────────────┤
                                                                        ▼
MatchPresenter.push(snapshot, events)  → feedback: sparks, rings, cues, hitstop request, impulses, haptics
MatchPresenter.render(alpha, delta)    → interpolate last two snapshots → pose passive proxies → camera
DuelHud.update(snapshot)               → health, pips, round, low-time clock, banner (writes only on change)
```

`MatchScreen` (application) owns the loop; presentation emits only requests and intents (`hitstop_requested`, `pause_pressed`, touch `move_changed` / `attack_*`).

## Change art, animation, or sound in one place (PRES-KIT-001)

Every content identity has one `PresentationKit` (`game/src/presentation/kit/presentation_kit.gd`): optional authored `scene`, `color_targets`, `visual_transform`, primitive sizes, `animation_clips` (semantic → clip), `audio_cues` (cue → stream), `vfx_cues`, trail and hitstop feel.

To replace the primitive look of an identity (e.g. a Blender model):

1. Import the `.glb` and wrap it in a scene (optional `AnimationPlayer` with clips).
2. Author a `PresentationKit` `.tres` at the identity's path in `RiposteKits.AUTHORED_KIT_PATHS` (`game/content/presentation/riposte_kits.gd`) with `id` set to the content id, `scene` pointing at the wrapper, and `animation_clips` / `audio_cues` filled in.
3. Nothing else changes. Authored kits load first; the factory primitive kit fills any gap. Debug builds fail closed on a missing kit; release builds use a placeholder.

Generic presentation code never names an identity (lint bans it); kits are resolved once per match (`DuelKits.resolve`).

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
| Arena scaffold (floor, ring, lights)                                                                      | `game/src/presentation/world/arena_scaffold.gd`                              |
| Duel camera (fixed orientation, smooth zoom, tiny impulses)                                               | `game/src/presentation/camera/`                                              |
| VFX (capped), audio (pooled voices; SFX + Music buses), haptics                                           | `game/src/presentation/vfx/`, `audio/`, `feedback/`                          |
| Coordinator                                                                                               | `game/src/presentation/match/match_presenter.gd`                             |
| HUD, pips, icons, debug overlay, HUD copy                                                                 | `game/src/presentation/hud/`                                                 |
| Touch controls (floating joystick + attack zone)                                                          | `game/src/presentation/input/touch_controls.gd`                              |

## Rules of thumb

- Proxies are passive: only `MatchPresenter.render` poses them.
- Feedback scales with physics (contact class, damage) and honors `PresentationOptions` (reduced motion disables camera impulses; reduced flash dims effects; hitstop still conveys impact). Per-identity feel (hitstop, trails) lives in kits; generic feel (spark counts, ring sizes, swing mix, impulse tiers) is named constants at the top of `MatchPresenter`, `VfxDirector`, and the proxies.
- Styling goes through `RiposteTheme`: components pick a `theme_type_variation` (`HudPlate`, `HudStack`, `HudRow`, `HudTitleLabel`, `HudAccentLabel`, `PlayerHealthBar`, …). The only per-node style is runtime safe-area margins (`RiposteTheme.apply_insets`).
- Blades render without depth test so the sword is always readable (combat-critical information).
- Icons are drawn shapes (`HudIcons`, `PipRow`), never glyphs the shipped font lacks.
- Audio: kit cues on the SFX bus; the arena kit's `music` cue loops on the Music bus while a duel is mounted.
