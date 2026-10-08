class_name PresentationFighter
extends RefCounted

## Read-only presentation facts for one fighter at one tick. Gameplay plane
## coordinates; world projection happens in ArenaTransform.
##
## See also: /docs/concepts/presentation.md

var slot: int = 0
## Which end of the arena this fighter holds (SIDE-001). Presentation reads it
## for identity (colour, home arc) and for the local camera orientation; it
## never decides anything in the simulation.
var side: DuelSide.Id = DuelSide.Id.LIGHT_SOUTH
var x: float = 0.0
var y: float = 0.0
var facing: float = 0.0
## Body velocity (m/s). Carried rather than differenced between snapshots,
## because a difference is an estimate and a hitstop or a dropped frame makes
## it a wrong one.
var vx: float = 0.0
var vy: float = 0.0
## Absolute blade angle and relative sword angle (radians, CCW).
var blade_angle: float = 0.0
var weapon_angle: float = 0.0
## |angular speed| of the blade (rad/s), drives trails and swing feel.
var blade_speed: float = 0.0
## Linear speed of the blade tip (m/s). The quantity that actually matters for
## readability: an arc looks dangerous because its tip is moving, and a short
## weapon swinging at the same angular rate is not the same threat.
var tip_speed: float = 0.0
## Which way the blade is turning: `+1` or `-1`. `tip_speed` is a magnitude,
## and a magnitude cannot say which side of the blade the edge is leading.
var swing_dir: float = 1.0
var charge: float = 0.0
## Motor authority this swing was launched with, and how far through its
## commanded arc the blade physically is. Travel, not elapsed time — a sword
## stopped by another sword has stopped progressing (COMBAT-009).
var launch_readiness: float = 0.0
var swing_progress: float = 0.0
## How dangerous this part of this swing is, in [0, 1], before anything about
## the opponent. Drives trail width and swing audio. It is deliberately *not*
## a prediction: convergence only exists at contact, so nothing before contact
## may promise it.
var swing_potential: float = 0.0
var phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
var commitment: float = 0.0
var stability: float = 1.0
## How exposed this fighter currently is, in [0, 1]. Read from their own
## physical state, which is what lets vulnerability be shown honestly — a
## displaced weapon, a committed swing, a bad angle — rather than as a meter
## predicting someone else's hit.
var exposure: float = 0.0
## How badly the fighter is out-angled from their opponent (radians), and the
## side the blade is committed to. Both diagnostic.
var facing_error: float = 0.0
var stable_side: float = -1.0
var guard_region: GuardRegion.Id = GuardRegion.Id.BASELINE
var burst: MovementGestureState.BurstKind = MovementGestureState.BurstKind.NONE
var health: float = 0.0
var max_health: float = 1.0
## Exertion resource (STAMINA-001). Presentation reads these to drive a
## condition indicator and capability feedback — they never write them back.
var stamina: float = 0.0
var stamina_max: float = 0.0
## Motor capability in [floor, 1] from injury + fatigue (PHYS-003).
var capability: float = 1.0
## Coarse health band for HUD and CPU (FighterCondition).
var condition: FighterCondition.Id = FighterCondition.Id.HEALTHY
var body_radius: float = 0.0
var is_falling: bool = false
var hilt_radius: float = 0.0
var tip_radius: float = 0.0
var threat_time: float = 0.0

## ──────────── Combat readability state (Phase 9) ────────────────────────
## Normalized 0-1 quantities for monotonic visual/audio mapping. Preallocated
## scalar fields, never hashed/replayed/fed back. Presentation maps these into
## cues — the simulation never reads them. See /docs/concepts/presentation.md.
##
## Fields that already exist as raw values (charge, commitment, exposure,
## swing_progress, swing_potential, stability) are not duplicated; readability
## consumers read those directly. Only *missing* normalized readings live here.
var recovery_remaining01: float = 0.0  ## recovery_left / recovery_ticks (1 = just started, 0 = done; OVERSWING = 1)
var stamina01: float = 0.0            ## stamina / stamina_max (0 = empty, 1 = full)
var point_threat01: float = 0.0       ## Physics-derived tip axial closing (0 = safe, 1 = lethal line)
var movement_speed01: float = 0.0     ## speed / max_speed (0 = still, 1 = sprinting)
var burst01: float = 0.0              ## 1.0 during any burst, 0.0 otherwise


func is_alive() -> bool:
	return health > 0.0
