class_name BodySupportPose
extends RefCounted

## How the body holds the authoritative sword this frame: one deterministic
## mapping from the same interpolated θ the hilt track is evaluated at
## (PRES-STANCE-001). The hilt track `C(θ)` is the physics projection of θ;
## this is the human projection of it — torso effort, elbow-guide inputs,
## gather — so the body cannot drift from the sword. The proxy samples it once
## per frame and the rig hands it to `CombatPoseModifier3D` untouched.
##
## Support is continuous in θ. The guard bands (`GuardPoseField`) are readings
## with hysteresis for whatever needs a name; they never step the body. In
## guard the effort blends across the Long Guard corridor's edges and around
## the load angle with smoothsteps, so crossing a band moves the torso by a
## sliver, not a jump. Outside guard the phase sets the effort, as a cut in
## flight commits the whole chain whatever its angle. Mirrored: support reads
## |θ|, and only the stance (the coil caps) is side-dependent.
##
## See also: /docs/concepts/presentation.md

## How much of the full follow the body commits, by phase; in guard, by where
## the sword rests. Interpretation values, not measurements — the shape (quiet
## at the point, loaded off the shoulder, full through the swing, soft in
## recovery) is the contract, not the numbers.
const EFFORT_POINT := 0.23
const EFFORT_READY := 0.43
const EFFORT_LOAD := 0.6
const EFFORT_CHARGE := 0.71
const EFFORT_SWING := 1.0
const EFFORT_OVERSWING := 0.86
const EFFORT_RECOVERY := 0.5
const EFFORT_STAGGER := 0.25
## Half-width of the blend from ready to load support around the load angle.
const LOAD_BLEND := deg_to_rad(10.0)

## The authoritative relative sword angle (radians, − the fighter's right).
var sword_angle: float = 0.0
var phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
## The share of the full kinetic-chain follow the torso commits.
var effort: float = EFFORT_READY
## The cut's own angle through its arc (`CutPresentationCurve.cut_angle`).
var cut_angle: float = 0.0
## Charge gather (0–1) and how settled into the stance the pose is (0–1).
var gather: float = 0.0
var settled: float = 1.0
## Which shoulder holds the load: −1 right, +1 left, 0 at the point.
var load_side: float = 0.0
## How far the hands are carried toward the fighter's left (+) or right (−)
## (m), which places the reaching arm's elbow pole.
var hand_lateral: float = 0.0


func sample(angle: float, combat_phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL, side: float = 0.0, lateral: float = 0.0, gather_value: float = 0.0, settled_value: float = 1.0, cut: float = 0.0) -> BodySupportPose:
	sword_angle = angle
	phase = combat_phase
	load_side = side
	hand_lateral = lateral
	gather = gather_value
	settled = settled_value
	cut_angle = cut
	effort = effort_for(combat_phase, angle)
	return self


## The torso's follow share for `combat_phase` with the sword at `angle`. In
## guard it is a continuous function of |θ|: the point's quiet support inside
## the corridor, the ready support past its leave edge, the load support past
## the load angle.
static func effort_for(combat_phase: CombatPhase.Id, angle: float) -> float:
	match combat_phase:
		CombatPhase.Id.CHARGING:
			return EFFORT_CHARGE
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE:
			return EFFORT_SWING
		CombatPhase.Id.OVERSWING:
			return EFFORT_OVERSWING
		CombatPhase.Id.RECOVERY:
			return EFFORT_RECOVERY
		CombatPhase.Id.STAGGER:
			return EFFORT_STAGGER
		CombatPhase.Id.DEAD:
			return 0.0
		_:
			return guard_effort(angle)


static func guard_effort(angle: float) -> float:
	var mag := absf(angle)
	var ready := lerpf(EFFORT_POINT, EFFORT_READY, smoothstep(GuardPoseField.THRUST_ENTER, GuardPoseField.THRUST_LEAVE, mag))
	return lerpf(ready, EFFORT_LOAD, smoothstep(GuardPoseField.LOAD_ANGLE - LOAD_BLEND, GuardPoseField.LOAD_ANGLE + LOAD_BLEND, mag))
