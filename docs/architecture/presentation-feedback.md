# Presentation Feedback Architecture

> See also: [spec/invariants.md](../../spec/invariants.md) — PRES-001, PRES-002, PRES-KIT-001, HITSTOP-001, COMBAT-009
> See also: [docs/concepts/presentation.md](../concepts/presentation.md), [docs/concepts/combat.md](../concepts/combat.md)
> Source: `game/src/presentation/feedback/`, `game/src/presentation/match/match_presenter.gd`

## Principle

Physics creates the event; presentation exaggerates its meaning. The simulation knows nothing about camera shake, slow motion, or visual effects. All game-feel consequences derive from resolved domain events and the physical quantities they carry.

## Architecture (PRES-002)

```text
Simulation
    ↓
PresentationSnapshot + DuelEvents
    ↓
CombatFeedbackDirector (pure computation, no SceneTree)
    ├── CameraFeedback
    ├── FighterPresenter A/B
    ├── WeaponPresenter A/B
    ├── VfxPresenter
    ├── AudioPresenter
    └── PresentationTimeController
```

**Critical rule:** Nothing below `CombatFeedbackDirector` may modify authoritative state. Presentation reads. It never writes back.

### CombatFeedbackDirector

Pure mapping from `PresentationSnapshot` + `DuelEvent[]` + `PlayerSettings` → `FeedbackFrame`. No node references, no SceneTree dependency. Outputs typed value-like requests:

```text
FeedbackFrame
    camera_requests: Array[CameraShakeRequest]
    fighter_requests: Array[FighterCueRequest]
    weapon_requests: Array[WeaponCueRequest]
    audio_requests: Array[AudioCueRequest]
    vfx_requests: Array[VfxRequest]
    hitstop_requests: Array[HitstopRequest]
```

The director does not know where the camera node lives, which bus plays sound, or how a spark is drawn. It classifies events and maps physical quantities to semantic presentation instructions.

### CameraFeedback

Consumes `CameraShakeRequest`, produces a camera offset. Owns:

- **Trauma accumulation:** `trauma = clamp(trauma + input, 0, 1)`, `amplitude = trauma²`
- **Directional kick:** initial kick follows `-impact_normal`, then decays
- **Coherent noise:** deterministic, not per-frame random teleport
- **Settings scaling:** everything multiplied by `PlayerSettings.screen_shake`
- **Decay:** exponential per wall-clock delta

`CameraController` combines: base framing/interpolation + presentation shake offset.

### PresentationTimeController

Consumes `HitstopRequest`, calls `FixedTickDriver.hold()`. This indirection exists because hitstop belongs to presentation orchestration, not impact classification. The director decides duration from `ImpactFeedback` + kit hitstop bands; the controller executes it. Wall-clock only (HITSTOP-001).

## Camera shake

- Normalized 0–100 semantic intensity, not pixel displacement.
- Normal hit: `round(severity01 × 50)`. Lethal blow: override to 100.
- Contact type adjusts shape, not raw magnitude:
  - Blade clash: short / high-frequency
  - Body hit: heavier / lower-frequency
  - Poke: small directional jab
  - Thrust: strong axial kick
- Multiply everything by `PlayerSettings.screen_shake`.
- Trauma model: `trauma = clamp(trauma + input, 0, 1)`, `amplitude = trauma^2` (or `trauma^3`). Small impacts subtle; multiple clashes accumulate; lethal impacts exceptional.
- Camera offset only. Never moves gameplay coordinates.

## Killing blow sequence

```text
lethal contact → impact freeze (~40–80 ms) → 100-shake impulse
→ slow-motion death presentation (0.15–0.35×) → death animation
→ round result
```

Slow motion is animation-side time scaling via `PresentationTimeController`, not `Engine.time_scale`. The authoritative simulation stays at 60 Hz.

## Kit architecture (PRES-KIT-001)

```text
CombatantPresentationKit
    fighter: FighterPresentationKit
    weapon: WeaponPresentationKit
```

### FighterPresentationKit

```text
scene                    # Optional authored scene (Blender .glb wrapper)
animation_map            # Semantic → clip
material_profile

Semantic animation slots:
  idle, move_forward, move_backward, orbit_left, orbit_right
  dash_forward, dash_back, dash_left, dash_right
  charge, swing, overswing, recovery
  hurt, critical, death

Audio:
  footstep, exertion, hurt, death

condition_visual_profile  # HEALTHY → HURT → WOUNDED → CRITICAL
```

### WeaponPresentationKit

```text
scene                    # Optional authored scene
grip/socket metadata

trail_profile, sweet_spot_profile, tip_profile

Audio:
  swing, clash, poke, thrust, slash

spark_profile, impact_profile
```

### Composition

```text
same fighter + bastard sword → works
same fighter + greatsword → works
different fighter + same sword → works
```

## Contact profiles: shared semantic + kit cosmetic

### Shared ImpactPresentationProfile

Defines the game language — every contact type has one semantic profile:

| Type   | Shake curve  | Hitstop band        | Baseline particles | Audio category |
| ------ | ------------ | ------------------- | ------------------ | -------------- |
| clash  | short/sharp  | hitstop_blade       | medium sparks      | metallic       |
| slash  | lower/heavy  | hitstop_body        | directional        | cut            |
| poke   | narrow jab   | hitstop_body        | minimal            | pierce         |
| thrust | strong axial | hitstop_body        | narrow burst       | deep pierce    |
| graze  | minimal      | minimal             | trace sparks       | scrape         |
| kill   | override 100 | hitstop_devastating | full burst         | devastating    |

### Weapon kit cosmetic overrides

May override: audio family, spark look, trail look, material response. MUST NOT redefine the meaning of a contact class. Readability stays consistent across weapons.

## Authoritative weapon motion

The sword's visual transform is driven by:

```text
SIMULATION WEAPON ANGLE + FIGHTER TRANSFORM → WeaponPresenter → visual transform
```

not by animation clips. Character animation visually supports the authoritative sword position. For Blender models, `AnimationTree` layers/blends:

```text
base locomotion + combat phase + condition layer + dash one-shot
+ procedural upper-body / weapon alignment
```

Root motion MUST NOT determine fighter position; the authoritative body simulation does that.

## Scene interface contracts (for Blender)

### Fighter visual scene

```text
ModelRoot
Skeleton3D           [later, for rigged models]
AnimationPlayer
optional AnimationTree
WeaponSocket         [marker node for weapon attachment]
optional VfxAnchors
```

### Weapon visual scene

```text
MeshRoot
GripSocket           [attachment point]
TipMarker            [for trail start]
TrailStart / TrailEnd
```

Imported scenes are validated against these contracts. Godot's recommended workflow: imported animations live in `AnimationPlayer`, `AnimationTree` handles transitions/blending, runtime control through tree instance parameters rather than mutating shared resources.

## Primitive presenters (MVP)

```text
PrimitiveFighterPresenter → cylinder (lean, dash compression, hurt posture, death fall)
PrimitiveWeaponPresenter  → line/capsule (rotation from authoritative angle, trail, sweet-spot, clash)
```

These implement the same interfaces as the final Blender presenters. Later:

```text
BlenderFighterPresenter → rigged model + AnimationTree
BlenderWeaponPresenter  → mesh + procedural alignment
```

No upstream changes. The primitive→Blender swap is a kit edit and a presenter swap, not an architecture change.

## Damage state

Damage presentation belongs to `FighterPresentationKit.condition_profile`, not `WeaponPresentationKit`:

```text
HEALTHY → HURT → WOUNDED → CRITICAL
```

Maps to: posture changes, breathing, idle instability, wound visual cues, animation layering.

## Mobile constraints

60 FPS target on mobile/web. Rules for trails, particles, and impact effects:

- Narrow sword trails, short lifetime
- Low particle count, small GPU particle bursts
- No giant fullscreen transparent overlays
- Minimize layered additive/transparent quads
- Prefer opaque/emissive geometry where possible
- A switched-off cue costs nothing per frame

## Blender pipeline (future)

```text
assets-src/
    fighter_a.blend
    bastard_sword.blend

pnpm game:assets
→ blender --background --python export_assets.py
→ game/assets/generated/
    fighter_a.glb
    bastard_sword.glb

Godot auto-import → PresentationKit .tres → runtime presenters
```

Source of truth: `.blend` files + export script + `.glb` output policy + `.tres` kit definitions. Not `.godot/imported/`. CI-reproducible without Blender installed (committed `.glb` or fetched artifacts).
