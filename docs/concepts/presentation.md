# Presentation

> See also: [spec/invariants.md](../../spec/invariants.md) — PRES-001, PRES-KIT-001, HITSTOP-001, UX-001, COMBAT-009
> See also: [docs/concepts/ux.md](./ux.md), [docs/concepts/simulation.md](./simulation.md), [docs/concepts/combat.md](./combat.md)
> See also: [docs/reference/godot.md](../reference/godot.md) — the rig and animation contract for authored scenes
> See also: [docs/reference/assets.md](../reference/assets.md) — the Blender and ElevenLabs asset pipeline
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

1. Import the `.glb` and wrap it in a scene (optional `AnimationPlayer` with clips). The pipeline is [docs/reference/assets.md](../reference/assets.md).
2. Author a kit `.tres` at the identity's path in `RiposteKits.AUTHORED_KIT_PATHS` (`game/content/presentation/riposte_kits.gd`) with the scene, animation clips (semantic → clip), and audio cues filled in.
3. Nothing else changes. Authored kits load first; the factory primitive kit fills any gap — a whole identity not yet authored, or any cue or intro an authored kit leaves out, so a half-authored identity is never silent. Debug builds fail closed on a missing kit; release builds use a placeholder.

Generic presentation code never names an identity (lint bans it); kits are resolved once per match (`DuelKits.resolve`).

The authoritative weapon angle drives the blade visual. Character animation visually supports the sword position, never the reverse. See [docs/architecture/presentation-feedback.md](../architecture/presentation-feedback.md) for the full architecture.

### Composition layers: skins, voice, intro, match loadout

Cosmetic and match-wide layers sit on top of the identity kits, and every one is optional — `null` means "the base kit's look":

| Layer                              | Holds                                                                     | Resolved                                     |
| ---------------------------------- | ------------------------------------------------------------------------- | -------------------------------------------- |
| `FighterSkinKit` / `WeaponSkinKit` | a replacement scene, or node → mesh (`null` hides) and material overrides | per slot, by skin id, from the catalog       |
| `FighterVoiceKit`                  | the announcer's reading of the name, effort and hurt takes                | on the fighter kit                           |
| `FighterIntroProfile`              | card text, spoken line and caption, the flourish clip                     | on the fighter kit                           |
| `MatchPresentationLoadout`         | arena kit, `AnnouncerKit`, `UiThemeKit`, `VfxStyleKit`                    | once per match (`RiposteKits.match_loadout`) |

`CombatantPresentationKit.of(fighter, weapon, skin, blade_skin)` refuses a skin authored for a different base kit, and an unknown skin id is the base look. Skins are chosen _after_ the rules are fixed (only the local player's slot wears the chosen one) and nothing in them can reach a definition, so reach, mass, and the state hash cannot change with a skin (PRES-RIG proves it with the Training Gear skin).

## Force-scaled feedback

There are no light/medium/heavy buckets. Every channel of a body strike reads one continuous `CombatFeedbackDirector.response()` of the resolver's own quality — flat at the bottom so a graze is barely there, full at the top of an ordinary strike, still growing into the devastating range — so there is no step anywhere along the ladder (PRES-FEEDBACK sweeps it). Contact _kind_ picks the shape (a slash fans, a poke or thrust draws an axial line); it never picks the size. Light and heavy body audio crossfade by damage rather than switching at a threshold.

A lethal blow adds the exceptional stack: the signature accent layer, a lethal flash, one longer freeze, and presentation-only slow motion (`SlowMotionRequest` → `FixedTickDriver.slow_motion`). Like hitstop, slow motion changes only _when_ ticks run, never what they compute (HITSTOP-001). A bind holds its grind and grind sparks for as long as the snapshot says the blades are pinned. `particle_intensity` 0 drops every particle while flash, streak, sound, and pacing still mark the hit.

A **killing blow** produces a `DeathPresentationRequest` — who died, the contact family (a slash cuts down, a thrust runs through), the direction the blow travelled, how hard it landed, and a deterministic key. The lock is the kill, not the stab: the director emits it **only on the blow that leaves the target not alive** (read from the post-tick snapshot), so a non-lethal poke or shallow thrust lands its contact feel and nothing more.

The request goes to a `DeathPresentationController`, which hands it — once per fighter per round — to the first **backend** that can carry it out. Today that is `PrimitiveDeathBackend`. On a killing **thrust** it also holds the striker in the run-through (the forward-burst lunge, held for the kill beat) — and because it is reached only from a death request, a thrust that does not kill can never lock the striker; a killing cut leaves the striker to follow through on their own swing. The victim's collapse is chosen from the kit's `DeathPresentationProfile`. An authored fighter maps styles to clips (`style_clips`), falling back to its generic `DEATH` clip and then to the procedural collapse; the Wolf falls backward onto his back for a cut (`death`) and folds over the blade, drops to his knees, and pitches forward face-down for a run-through (`death_stab`), while the striker holds the driven lunge (`finisher_clip` → `run_through`) rather than the dash, which steps back to guard on its own. On the primitive body the same styles are procedural: a cut drops it backward, a stab pitches it forward, folding styles sink it. A one-shot clip holds its last frame for as long as its state lasts — the proxy starts a clip when the clip changes, never because the last one ended — so a dead body stays down. A **ragdoll** is a future optional backend placed ahead of the primitive, not a replacement: it is added only once the rig's `Skeleton3D` has a generated, trimmed `PhysicalBoneSimulator3D` and web/mobile profiling shows it earns its cost — until then the controller falls through to the primitive. Whatever backend runs, it lives on a presentation-only collision layer, starts from the current rendered pose rather than bind pose, and never reports back, so it cannot change a hit, a ring-out, the winner, or the replay hash. Unit tests cover the request and the orchestration (one start per death, fall-through when a backend is unavailable) against a fake backend; actual ragdoll motion is a device-QA pass, never a unit assertion.

A **ring-out** is not a death and is never an immediate ragdoll. The simulation ends the round the tick a fighter crosses the edge, so authority stops moving them at the lip; the director then emits a `FallPresentationRequest` carrying the exact exit position and the horizontal momentum carried over the edge, and the proxy's fall **owns the root trajectory** from there (`root_at`: exit momentum carried forward unchanged, presentation gravity drawing the body down). A fighter shoved hard flies out; one who stepped off drops near the edge — the fall reads the knockback that caused it rather than dropping straight down at the lip. A raw ragdoll started at the ledge could flop backward or snag and visually deny that knockback, so the root always follows this trajectory; a ragdoll may later own only the limbs.

A fighter out of the round **drops their sword**: the dead hand goes slack as the collapse begins (`WeaponDropRequest.DEATH_DELAY`), and over the edge the hands let go a deterministic beat after the ledge (0.15–0.35 s from the event key). A survived hit never drops it. When the hands let go, the held look is hidden — the simulation-posed pivot itself never moves — and a `DroppedWeapon3D` rigid body carries a copy of it, launched with the blade's own spin from the authoritative blade angle and speed plus the presented body's motion at that instant (still for a collapse in place, the fall trajectory over the edge), so the exit momentum is never counted twice. The arm IK eases off the empty grip, and the next round clears the floor and puts the sword back in hand. Presentation physics uses its own layers (`PresentationPhysicsLayers`): the sword collides only with the presentation floor (the platform top at the rules' radius, on either arena path), so it lands inside the edge and falls past it, and nothing authoritative is touched — Riposte's combat uses no Godot physics at all. When and how the sword drops is unit-tested; its tumble is device QA.

A **parry** is given a physical deflection read whose brightness is the beat margin (`DuelEventKeys.MARGIN`, how far ahead the defender became threatening): a decisive deflection flashes a tighter ring, throws a hotter spark fan, rings a crisper and higher clash cue, and snaps the camera harder than a bare-threshold one. Riposte has no parry button and no parry bonus, so this feedback **borrows none of a hit's weight** — no hitstop, no slow motion, no damage, no stun. It only tells the eye how cleanly the simulation's deflection landed.

## Authored audio

A cue may hold one stream or an array of takes. The take for an event is chosen from `CombatFeedbackDirector.variant_key` (tick, actor, target), so a replay hears the same takes in the same order. `audio_layers` name cues that sound with a primary from the same event (a strong clash is transient + metal tail + low impact). Buses: Master → Music, SFX (→ Combat, UI), Voice; announcer volume and captions are player settings. Every voiced line requests a caption, even when the line is missing or muted.

## Set introduction

The first match of a Quick Play set opens with `SetIntroDirector` (~2.6 s): the first fighter's close-up and card, a versus beat, the second fighter, then a cut back to the gameplay camera and the duel call. Rematches and new rounds are the same set and are never introduced. The clock is stopped for the whole intro, so the first authoritative tick is identical with or without it; any deliberate press skips it and never becomes an attack. The showcase figures are display-only (`FighterShowcasePresenter`): their swords perform an authored flourish, because no collision exists during the shot. What the announcer reads is content: Wolf, introduced first, is read "Wold." (`FighterIntroProfile.spoken_override_first_slot`).

## HUD and world

The HUD is ornament over information: mirrored charcoal plates with gold edging and asymmetric corners, sword-point diamond pips, restrained health and stamina rules, and condition repeated as a _shape_ icon plus a word — the body in the world carries it first. Banners slash in and snap out (Reduced Motion keeps the text and drops the slash). Gold is decorative only; every text pair stays a proven `TEXT_PAIRS` combination. Menu buttons get a fast scale pulse and UI sounds through `UiFeedback`.

The duel space is a lit warm-stone platform over a near-black void, with a warm key, a faint cool rim, an emissive gold warning ring, and braziers on the perimeter. The floor stays a mid stone on purpose: its luminance is where both a light and a dark combatant clear 3:1 (`WORLD_READS`), and an authored fighter's dominant clothing is validated against the same floor at export.

## Authored rigs follow the sword

An authored fighter scene's root carries `SwordRig3D`. At build the proxy binds it to its `SwordPivot`; every frame it passes the authoritative angle. The skeleton's stack runs animation (feet, hips, spine, head), then `KineticChainModifier3D` (the body supports the sword as a chain — chest most, spine less, hips least, head counter-rotating to the opponent — with phase-dependent effort read from the combat phase and `GuardPoseField` band), then a two-setting `TwoBoneIK3D` that locks each palm to its grip marker with elbows poled laterally and forward of the chest. PRES-RIG sweeps the whole legal arc (±135°): palms stay on the grip, no elbow inverts, the blade stays exactly where the simulation put it, and a neutral-guard case proves the elbows project out of the torso silhouette. Over an authored blade the x-ray blade becomes a faint ghost, so the sword still reads through bodies; High Contrast Weapons restores the full core.

### The guard is a continuous HEMA field, not one named pose

The simulation has one blade swung freely, so it has no discrete left/right guard — only a relative angle. Presentation reads that angle as a point on a **continuous field** (`GuardPoseField`), running

```
LEFT_WIND_BACK — LEFT_READY — LONGPOINT — RIGHT_READY — RIGHT_WIND_BACK
```

so a point held forward reads as **Longpoint**, a drawn-in guard reads as a ready side guard, and a cut wound back off a shoulder reads as a loaded **Mittelhut**. Mittelhut is therefore one reading on the field (the wound-back end), not the name of every neutral posture. The field never decides anything — it only tells the body how to carry the blade the physics already placed (PRES-001). The thrust corridor around centre has **hysteresis**: a near-straight blade must swing clearly off-centre (past `THRUST_LEAVE`) before the body commits to a side, and must come clearly back inside (`THRUST_ENTER`) before it lets go of Longpoint. A side change always passes through Longpoint, so the body never snaps across centre and a blade wavering around 0° never flickers.

The body supports the sword as a kinetic chain (chest most, spine less, hips least, head counter-rotating to stay on the opponent), but the follow is **phase-dependent effort**, not a permanent function of the angle (`KineticChainModifier3D.effort_scale`): quiet at a held point, more loaded off the shoulder, peaking through the swing (full commit), easing in `OVERSWING`, soft in `RECOVERY`, and gone when `DEAD`. The horizontal slash reads as a **Mittelhau** — a committed middle cut, arms progressively extending toward ~150–170°, never hyperextended — and because the sword is authoritative there is no canned `right → left` clip: the blade rotates, the chain carries the body through, and the follow-through becomes the next guard.

**The gameplay blade is never pitched out of plane to sell a stance.** The authoritative sword stays in its plane; a high oblique "45° guard" is read from the _body_ — hilt height, shoulder line, wrist carriage, weight — not by tilting the blade the simulation placed (any blade elevation stays a shallow read, well under ~18°). A full 45°+ blade tilt is reserved for terminal presentation (intro, victory, death), where the simulation no longer owns the pose. The feet follow locomotion and a weight shift loads the cut; the body does **not** swap which foot leads every time the sword crosses sides, and Wolf keeps his right foot slightly forward as identity. A walking **poke** stays animation-free beyond the point-forward body support; a committed **thrust** gets the procedural lunge/body-support lean (the forward burst already carries it). The guard, cut, pose-field, and effort contracts live beside the rig in `SwordRig3D`, `GuardPoseField`, and `KineticChainModifier3D`.

## Components

| Component                                                                                                 | Code                                                                         |
| --------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| Theme (palette, sizes, fonts, styleboxes, container defaults, type variations) — the game's `globals.css` | `game/src/presentation/theme/riposte_theme.gd`                               |
| Audio buses (Master → Music, SFX → Combat/UI, Voice), loaded by the engine before anything plays          | `game/default_bus_layout.tres`, `game/src/presentation/audio/audio_buses.gd` |
| Set introduction and display-only showcase                                                                | `game/src/presentation/intro/`                                               |
| Authored models, rigs, and audio takes                                                                    | `game/assets/`, `art-src/blender/` ([assets](../reference/assets.md))        |
| Kits, catalog, per-match kit set                                                                          | `game/src/presentation/kit/`                                                 |
| MVP-0 kits, camera profile, procedural audio                                                              | `game/content/presentation/`                                                 |
| Snapshot + projector (the only read boundary)                                                             | `game/src/presentation/snapshot/`                                            |
| Arena axes: world = (x, 0, −y), yaw = θ + π/2                                                             | `game/src/presentation/spatial/arena_transform.gd`                           |
| Passive fighter proxy (primitive or authored; x-ray blade) and sword trail                                | `game/src/presentation/entities/`                                            |
| Death presentation: request → controller → backend (primitive now, ragdoll later)                         | `game/src/presentation/death/`                                               |
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
- Audio: combat cues on the Combat bus, round stings on SFX, menu cues on UI, the announcer on Voice; the arena kit's `music` cue loops on the Music bus while a duel is mounted.
