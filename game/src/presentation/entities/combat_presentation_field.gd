class_name CombatPresentationField
extends RefCounted

## How a fencer lifts the sword the simulation placed: a pure, deterministic
## mapping from authoritative weapon state to the height, pitch and roll of the
## displayed sword (PRES-CARRIAGE-001, WEAPON-ORBIT-006). Nothing horizontal:
## the carriage (grip centre) is the authoritative `C(θ)` and the blade's yaw
## is θ, handed in from `WeaponKinematics` at the interpolated angle, so
## collision, the drawn sword and the hands share one planar transform
## (WEAPON-ORBIT-005). The sword pitches and rolls about that carriage; the
## hands follow the displayed sword (two-hand IK), never the reverse, and
## nothing here is written back.
##
##   authoritative θ → C(θ)                      (WeaponKinematics: where)
##   phase, swing progress, charge, launch charge → height, pitch, roll   ← this class
##     → displayed sword → grip markers → arms
##
## Long Guard, Ready, Gather and Load are readings of the one continuous θ:
## the orbit already carries the hands forward near the centre and back toward
## the shoulder further round; the lift only says how high and how steep.
##
## - **Guard** (θ alone): near level at Long Guard, the point a little raised
##   through Ready, steeper wound far round.
## - **Charge gather**: the hold lifts the hands toward shoulder height and the
##   point high (~65°) — Vom Tag at the shoulder / Zornhut — over whatever side
##   θ has wound to. Charge reads mostly as point height.
## - **Cut** (`CutPresentationCurve`): on release the loaded sword descends as
##   the blade travels, near level through the centre where contact happens, a
##   slight dip past it, then the pitch inflection into the opposite guard. A
##   right and a left release mirror into the X of Riposte's slash language.
##   Progress is physical travel (COMBAT-009), so a blade stopped or turned by
##   contact stops or reverses the picture.
##
## Coordinates are the fighter's VisualRoot (the combat frame): +X the
## fighter's left, +Y up, +Z forward. Angles: 0 = point forward, negative = the
## fighter's right. The numbers are presentation tuning for the baseline
## fencer's proportions, judged by silhouette (PRES-RIG and the visual gate).
##
## Implements: /spec/invariants.md#weapon-orbit-006
## See also: /docs/concepts/presentation.md

## Guard keys over |θ| (degrees): 0 Long Guard, 45 Ready, 90 the edge of the
## ready band, 135 wound fully round. Hands' height above blade height, and the
## blade's pitch. Wound fully round without a charge (a rebound, a recovery)
## the blade stays low and shallow, under the heroic head the bladed stance
## carries toward the hands (PRES-RIG). Steeper, or a higher hand, it rises
## through that head; a charge's gather lifts it to the load's own pitch instead.
const STANCE_DEGREES: PackedFloat64Array = [0.0, 45.0, 90.0, 135.0]
const STANCE_RAISE: PackedFloat64Array = [0.17, 0.17, 0.15, 0.18]
const STANCE_PITCH_DEGREES: PackedFloat64Array = [10.0, 12.0, 8.0, 4.0]

## The high shoulder load at full charge: the hands at shoulder height, the
## point high.
const LOAD_RAISE := 0.42
const LOAD_PITCH_DEGREES := 65.0

## Swing progress over which a swing leaves its guard lift for the cut, and
## over which a loaded sword comes down off the shoulder.
const LEAVE_STANCE_END := 0.3
const DESCENT_END := 0.55

## Crossguard roll toward the blade's side off centre (wrist pronation): the
## side read of the inflection, never a flip.
const ROLL_DEGREES := 14.0
const ROLL_START := 20.0
const ROLL_END := 90.0

## Results of the last `sample`, in VisualRoot space. Preallocated: one field
## per proxy, sampled every frame.
## The displayed sword's mount: origin at the pommel, +Z down the blade.
var transform := Transform3D.IDENTITY
## The carriage, lifted: the orbit's reference point on the drawn sword. The
## hands hold the grip either side of it toward the pommel.
var carriage_point := Vector3.ZERO
## The lift itself: hands' height above blade height (m), pitch and roll (rad).
var raise: float = 0.0
var pitch: float = 0.0
var roll: float = 0.0
## 1 = full guard lift, 0 = full cut lift.
var stance_weight: float = 1.0
## How far toward the high shoulder load the sword is gathered (0–1).
var gather: float = 0.0
## Pommel to carriage along the blade (m), the domain's `carriage_radius` —
## the drawn sword sits where collision says it does.
var carriage_radius: float = PhysicalBaseline.CARRIAGE_REFERENCE_M

var _angle: float = 0.0
var _carriage := Vector2.ZERO
var _blade_height: float = 0.0


## Lift the authoritative sword at `angle` (relative weapon angle θ) whose
## carriage sits `carriage_left` / `carriage_forward` in the combat frame, for
## `phase` at `progress` through the swing; `charge` is the hold's earned
## charge, `swing_charge` the charge the swing in flight was launched with;
## `blade_height` is the authoritative plane's height. Pure: the same inputs
## always give the same pose.
func sample(angle: float, carriage_left: float, carriage_forward: float, phase: CombatPhase.Id, progress: float, charge: float, swing_charge: float, blade_height: float, cut_dir: float = 1.0, committed: bool = false) -> CombatPresentationField:
	var degrees := rad_to_deg(absf(angle))
	var side := signf(angle)
	stance_weight = stance_weight_for(phase, progress)
	gather = gather_for(phase, progress, charge, swing_charge)
	var stance_raise := sample_keys(STANCE_DEGREES, STANCE_RAISE, degrees)
	var stance_pitch := deg_to_rad(sample_keys(STANCE_DEGREES, STANCE_PITCH_DEGREES, degrees))
	raise = stance_raise
	pitch = stance_pitch
	if stance_weight < 1.0:
		var a := CutPresentationCurve.cut_angle(angle, cut_dir)
		var share := CutPresentationCurve.stance_share(a, committed)
		var cut_raise := lerpf(CutPresentationCurve.raise(a), stance_raise, share)
		var cut_pitch := lerpf(CutPresentationCurve.pitch(a), stance_pitch, share)
		raise = lerpf(cut_raise, stance_raise, stance_weight)
		pitch = lerpf(cut_pitch, stance_pitch, stance_weight)
	if gather > 0.0:
		raise = lerpf(raise, LOAD_RAISE, gather)
		pitch = lerpf(pitch, deg_to_rad(LOAD_PITCH_DEGREES), gather)
	roll = -side * deg_to_rad(ROLL_DEGREES) * smoothstep(ROLL_START, ROLL_END, degrees)
	_angle = angle
	_carriage = Vector2(carriage_left, carriage_forward)
	_blade_height = blade_height
	compose()
	return self


## Rebuild `transform` and `carriage_point` from the last sample's carriage and yaw
## and the current `raise`, `pitch` and `roll` — for a caller that blends the
## lift (the proxy's inertialization). Never moves the carriage horizontally.
func compose() -> void:
	var basis := Basis.from_euler(Vector3(-pitch, _angle, roll), EULER_ORDER_YXZ)
	carriage_point = Vector3(_carriage.x, _blade_height + raise, _carriage.y)
	transform = Transform3D(basis, carriage_point - basis.z * carriage_radius)


## How much of the guard lift the sword holds rather than the cut's: all of it
## out of a cut; a swing (and a bind, where contact is the point) leaves the
## guard as the blade gets going, read from physical travel so a stopped blade
## stops changing; recovery is the cut's own follow-through, which rises back
## into the opposite guard through `CutPresentationCurve`'s inflection.
static func stance_weight_for(phase: CombatPhase.Id, progress: float) -> float:
	if phase == CombatPhase.Id.RECOVERY:
		return 0.0
	if not is_swing(phase):
		return 1.0
	return 1.0 - smoothstep(0.0, LEAVE_STANCE_END, clampf(progress, 0.0, 1.0))


## How far toward the high shoulder load the sword is gathered: the earned
## charge while holding (point height is the charge cue), and the launch charge
## coming down off the shoulder over the first part of the swing's travel.
static func gather_for(phase: CombatPhase.Id, progress: float, charge: float, swing_charge: float) -> float:
	if phase == CombatPhase.Id.CHARGING:
		return clampf(charge, 0.0, 1.0)
	if is_swing(phase):
		return clampf(swing_charge, 0.0, 1.0) * (1.0 - smoothstep(0.0, DESCENT_END, clampf(progress, 0.0, 1.0)))
	return 0.0


static func is_swing(phase: CombatPhase.Id) -> bool:
	match phase:
		CombatPhase.Id.LAUNCH, CombatPhase.Id.ACTIVE_EARLY, CombatPhase.Id.ACTIVE_THREAT, CombatPhase.Id.ACTIVE_LATE, CombatPhase.Id.OVERSWING:
			return true
		_:
			return false


## The displayed tip for this pose (VisualRoot space), `tip_length` from the
## pommel.
func tip(tip_length: float) -> Vector3:
	return transform * Vector3(0.0, 0.0, tip_length)


## Smooth interpolation through a key table: eased between keys, so the lift
## has no kinks at the keys and none through centre.
static func sample_keys(keys: PackedFloat64Array, values: PackedFloat64Array, at: float) -> float:
	if at <= keys[0]:
		return values[0]
	for index in range(1, keys.size()):
		if at <= keys[index]:
			var t := smoothstep(keys[index - 1], keys[index], at)
			return lerpf(values[index - 1], values[index], t)
	return values[values.size() - 1]
