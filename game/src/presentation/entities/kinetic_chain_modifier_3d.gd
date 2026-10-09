class_name KineticChainModifier3D
extends SkeletonModifier3D

## The body supports the authoritative sword as a kinetic chain, so a Mittelhau
## (horizontal cut) reads as a trained cut rather than a wrist flick: the chest
## follows the sword most, the spine less, the hips least, and the head
## counter-rotates to stay on the opponent. Runs after animation mixing and
## before arm IK, so the hands still lock to the grip and the blade is never
## moved by this (PRES-001).
##
## Shares are LOCAL yaw per bone, about each bone's own (vertical) axis. Because
## the spine chain nests Hips → Spine → Chest → Head, the cumulative WORLD yaw
## falls off down the chain: chest ends up turned most, hips least, and the
## head — a negative local share — ends up barely turned, i.e. still facing the
## opponent. These are presentation interpretation values, not Meyer
## measurements; what matters is the falloff ordering.
##
## See also: /docs/reference/godot.md, /docs/concepts/presentation.md

## bone → local share of the sword angle, at full (active-swing) effort.
## Cumulative world targets this implies at scale 1.0: hips 0.10, spine 0.20,
## chest 0.35, head 0.10 (counter-rotated). Effort below scales these down.
const LOCAL_SHARES := {
	&"Hips": 0.10,
	&"Spine": 0.10,
	&"Chest": 0.15,
	&"Head": -0.25,
}
## Parents before children, so each bone's local pose is set before the next.
const CHAIN: Array[StringName] = [&"Hips", &"Spine", &"Chest", &"Head"]

## How much of the full follow the body commits, by phase. The follow is not a
## permanent fixture of the sword angle — a held point barely turns the chest, a
## wound-back cut loads it, and the whole chain peaks through the swing and
## decays in recovery. In guard the scale comes from the guard band, so the body
## is quiet at the point and loaded off the shoulder. Interpretation values, not
## Meyer measurements — the shape (quiet guard, strong swing, soft recovery) is
## the contract, not the exact numbers.
const SCALE_THRUST := 0.23
const SCALE_READY := 0.43
const SCALE_WIND := 0.6
const SCALE_CHARGE := 0.71
const SCALE_SWING := 1.0
const SCALE_OVERSWING := 0.86
const SCALE_RECOVERY := 0.5
const SCALE_BIND := 0.34
const SCALE_STAGGER := 0.25

## The authoritative relative sword angle, set by the proxy each frame.
var sword_angle: float = 0.0
## The combat phase and (in guard) the guard band, set by the proxy each frame;
## together they choose how hard the body supports the blade this frame.
var combat_phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
var guard_band: GuardPoseField.Band = GuardPoseField.Band.READY


## How much of the full follow this phase commits (0 = none, 1 = full swing).
## In NEUTRAL the body is in guard, so effort is read from the guard band.
static func effort_scale(phase: CombatPhase.Id, band: GuardPoseField.Band) -> float:
	match phase:
		CombatPhase.Id.CHARGING:
			return SCALE_CHARGE
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE:
			return SCALE_SWING
		CombatPhase.Id.OVERSWING:
			return SCALE_OVERSWING
		CombatPhase.Id.RECOVERY:
			return SCALE_RECOVERY
		CombatPhase.Id.BIND:
			return SCALE_BIND
		CombatPhase.Id.STAGGER:
			return SCALE_STAGGER
		CombatPhase.Id.DEAD:
			return 0.0
		_:
			match band:
				GuardPoseField.Band.THRUST:
					return SCALE_THRUST
				GuardPoseField.Band.WIND:
					return SCALE_WIND
				_:
					return SCALE_READY


## Cumulative world yaw a bone reaches, following `CHAIN` order. Diagnostic and
## tested: proves the falloff (chest most, hips least, head counter-rotated).
## `scale` is the phase effort; the default (1.0) is full active-swing follow.
static func world_follow(bone: StringName, angle: float, effort: float = 1.0) -> float:
	var cumulative := 0.0
	for link: StringName in CHAIN:
		cumulative += float(LOCAL_SHARES[link]) * angle * effort
		if link == bone:
			return cumulative
	return 0.0


func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var effort := effort_scale(combat_phase, guard_band)
	for link: StringName in CHAIN:
		var bone := skeleton.find_bone(link)
		if bone < 0:
			continue
		var twist := Quaternion(Vector3.UP, float(LOCAL_SHARES[link]) * sword_angle * effort)
		skeleton.set_bone_pose_rotation(bone, skeleton.get_bone_pose_rotation(bone) * twist)
