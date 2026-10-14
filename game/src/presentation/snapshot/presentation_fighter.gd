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
## Combat heading φ (HEADING-001): the centre of the 270° weapon range and the
## fighter's aim. Stance and head face it; the body is bladed off it; the
## weapon frame hangs on it (PRES-HEADING-001).
var facing: float = 0.0
## Target bearing τ: exactly where the opponent is — what φ is trying to
## catch. The head may only glance toward it (`CombatPoseModifier3D.LOOK_LIMIT`).
var target_bearing: float = 0.0
## How much turning authority commitment leaves this tick (0–1), for debug and
## readability; the simulation's own value (`CommitmentModel.turn_torque_share`).
var turn_authority: float = 1.0
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
## The direction the current swing was launched in (+1 / −1), which a rebound
## does not change, and the sword's signed angular velocity relative to the
## body (rad/s; positive turns toward +angle). Together they say whether the
## blade is still travelling into the side its cut was aimed at.
var cut_dir: float = 1.0
var weapon_speed: float = 0.0
var charge: float = 0.0
## The charge the swing in flight was launched with (0 out of a swing, and for
## a tap). `charge` closes at release; this is how far the cut was loaded, so
## the drawn sword can descend from the height it was gathered to.
var swing_charge: float = 0.0
## Motor authority this swing was launched with, and how far through its
## commanded arc the blade physically is. Travel, not elapsed time — a sword
## stopped by another sword has stopped progressing (COMBAT-009).
var launch_preparation: float = 0.0
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
## predicting someone else's hit. Meaningful only when the snapshot
## `has_threat_readings`; otherwise the neutral default.
var exposure: float = 0.0
## How badly the fighter is out-angled from their opponent (radians), and the
## side the blade is committed to. Both diagnostic.
var facing_error: float = 0.0
var stable_side: float = -1.0
var guard_region: GuardRegion.Id = GuardRegion.Id.BASELINE
var burst: MovementGestureState.BurstKind = MovementGestureState.BurstKind.NONE
var health: float = 0.0
var max_health: float = 1.0
## The fighter's condition this tick (CONDITION-001), copied from the domain's
## own `ConditionModel` — for the debug overlay and telemetry. The player HUD
## shows health only; presentation never rederives these from health.
var force_scale: float = 1.0
var speed_scale: float = 1.0
var tracking_scale: float = 1.0
## Coarse health band for HUD and CPU (FighterCondition).
var condition: FighterCondition.Id = FighterCondition.Id.HEALTHY
var push_radius: float = 0.0
var is_falling: bool = false
## How this fighter left the round, read from authority (COMBAT-014): the one
## terminal presentation they get (PRES-TERMINAL-001).
var terminal_cause: FighterState.Terminal = FighterState.Terminal.NONE
## The body a killed fighter became (FallenBodyState), read-only: lying once
## its collapse is over, along `body_yaw` through its centre of mass (the
## fighter's position), turning at `body_spin`, and whether it went over the
## edge as a body.
var body_lying: bool = false
var body_yaw: float = 0.0
var body_spin: float = 0.0
var body_over_edge: bool = false
var hilt_radius: float = 0.0
var tip_radius: float = 0.0
## The fighter's immutable rules weapon, so presentation poses the planar sword
## with the same `WeaponKinematics` collision uses, at the interpolated angle
## (WEAPON-ORBIT-005). Geometry only: never read for an outcome.
var weapon_definition: WeaponDefinition
## Where the swing in flight is committed to end (rad, weapon angle); the
## debug overlay draws the immediate threat up to it.
var swing_end: float = 0.0
## The fighter's whole immutable physics (weapon, body, handling), for the
## same purpose: posing the planar sword on its own handling's track.
## Geometry only: never read for an outcome.
var combatant_spec: CombatantPhysicsSpec
## World velocity (m/s, gameplay plane) of the authoritative blade tip.
var tip_vx: float = 0.0
var tip_vy: float = 0.0
## The weapon's authored mass (kg). A dropped sword tumbles as the object the
## simulation modelled, never as a second approximate sword.
var weapon_mass: float = 0.0
## This fighter's time to threaten its opponent (s, `InitiativeModel`), for the
## debug overlay; meaningful only when the snapshot `has_threat_readings`.
var threat_time: float = 0.0

## ──────────── Combat readability state (Phase 9) ────────────────────────
## Normalized 0-1 quantities for monotonic visual/audio mapping. Preallocated
## scalar fields, never hashed/replayed/fed back. Presentation maps these into
## cues — the simulation never reads them. See /docs/concepts/presentation.md.
##
## Fields that already exist as raw values (charge, commitment, exposure,
## swing_progress, swing_potential, stability) are not duplicated; readability
## consumers read those directly. Only *missing* normalized readings live here.
var recovery_remaining01: float = 0.0  ## the recovery's own commitment decay (1 = just started, 0 = done; OVERSWING = 1)
var point_threat01: float = 0.0       ## Physics-derived tip axial closing (0 = safe, 1 = lethal line)
var movement_speed01: float = 0.0     ## speed / max_speed (0 = still, 1 = sprinting)
var burst01: float = 0.0              ## 1.0 during any burst, 0.0 otherwise


func is_alive() -> bool:
	return health > 0.0
