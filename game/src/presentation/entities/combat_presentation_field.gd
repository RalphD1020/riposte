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
## Long Guard (Langort-inspired, PRES-LONGPOINT-001) lifts the hands a little
## above Ready. Higher costs the bladed left arm its Long Guard extension at the
## corridor's edge (with the hands aimed along the forearms, 0.22 measured
## 0.865 at −18° against PRES-RIG's 0.88): on the 0.63 m hilt track a lift
## cannot lengthen the arms, only the track can, and that is a rules change.
const STANCE_RAISE: PackedFloat64Array = [0.19, 0.17, 0.15, 0.18]
const STANCE_PITCH_DEGREES: PackedFloat64Array = [10.0, 12.0, 8.0, 4.0]

## The high shoulder load at full charge: the hands at shoulder height, the
## point high.
const LOAD_RAISE := 0.42
const LOAD_PITCH_DEGREES := 65.0

## Swing progress over which a swing leaves its guard lift for the cut, and
## over which a loaded sword comes down off the shoulder.
const LEAVE_STANCE_END := 0.3
const DESCENT_END := 0.55

## The shared X projection's normalized height on the attack-origin side
## (`x = σ·θ`): Ready 0.75, gather 0.88, full wind-back 1.00 — the share of the
## way from the Ready lift to a body's declared high guard is
## `(height − 0.75) / 0.25` (0 at 45°, 0.52 at 90°, 1 at 135°). Presentation
## landmarks, fitted from anatomy, never a physical height.
const X_HIGH_DEGREES: PackedFloat64Array = [45.0, 90.0, 135.0]
const X_HIGH_HEIGHT: PackedFloat64Array = [0.75, 0.88, 1.0]
## The angular step over which the strike region's direction of travel is read
## when the long edge leads the motion.
const EDGE_PROBE_RAD := deg_to_rad(0.5)

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
## This field's guard keys: the shared tables unless the scene declares a
## different centre (`configure_centre`).
var _stance_raise: PackedFloat64Array = STANCE_RAISE
var _stance_pitch: PackedFloat64Array = STANCE_PITCH_DEGREES
## The combat-aligned projection (a body's declared choice): the drawn sword
## level (pitch 0, roll 0) at one fixed interaction height in every phase, so
## two swords that touch on the plane already touch in 3D. It is the
## footprint-parity reference, not the product X: it erases the raised guard
## (CONTACT-PRESENTATION-001). The guard, gather and cut weights are still read
## (the arm poses follow them); only the sword's lift is fixed. Off (the shared
## lifts) on every shipping body.
var combat_aligned: bool = false
var interaction_raise: float = 0.0
## This body's charged-cut load: hands' height above the plane and blade pitch
## at the full wind-back. When the body declares its high guard
## (`configure_load(..., true, ...)`) the lift is angle-driven by the shared X
## projection instead of gather-driven: on the attack-origin side the guard keys
## at 90° and 135° rise from Ready toward the high guard (`_high_raise` /
## `_high_pitch`) and the blade rolls about its own axis toward that side's
## roll (θ < 0 the right load) by the same share — one continuous angle, so the
## crossguard never jumps through another orientation — and a charge adds no
## lift of its own (where the blade is decides how high it is drawn). The far
## side of a cut keeps the shared low lift. The shared constants, gather lift
## and side-signed guard roll on every shipping body.
## The most the left high guard's roll may depart from the mirror of the right's
## (degrees): a small right-handed correction, never a second, independent pose.
const LOAD_ROLL_CORRECTION_LIMIT := 15.0
var _load_raise: float = LOAD_RAISE
var _load_pitch: float = deg_to_rad(LOAD_PITCH_DEGREES)
var _load_roll_authored: bool = false
var _load_roll_right: float = 0.0
var _load_roll_left: float = 0.0
var _high_raise: PackedFloat64Array = STANCE_RAISE
var _high_pitch: PackedFloat64Array = STANCE_PITCH_DEGREES
## The long edge leads the motion (a body's declared choice, `configure_edge`):
## the blade's roll is derived each sample from the strike region's direction of
## travel in the cut direction (`edge_roll`) instead of the side-signed guard
## roll and the high guard's authored rolls, so the same edge leads through the
## load, the descent, the centre and the follow-through of both diagonals.
## Off on every shipping body.
var _edge_leads: bool = false
var _edge_radius: float = 0.0
var _edge_previous: float = NAN
## The cutting edge's angle from +X in the sword frame (0 for edge A, π for B).
var _edge_offset: float = 0.0


## A body's own Long Guard key: the centre's hand height and blade pitch moved
## by the scene's declared deltas (m, degrees), eased into the unchanged Ready
## key like any other. Built once when the body binds; zero deltas are the
## shared tables exactly.
func configure_centre(raise_delta: float, pitch_delta_degrees: float) -> void:
	_stance_raise = STANCE_RAISE.duplicate()
	_stance_pitch = STANCE_PITCH_DEGREES.duplicate()
	_stance_raise[0] += raise_delta
	_stance_pitch[0] += pitch_delta_degrees


## The left load's roll for a right load's `right_roll` (radians): its mirror
## image, plus a right-handed correction clamped to `LOAD_ROLL_CORRECTION_LIMIT`.
static func mirrored_load_roll(right_roll: float, left_correction: float) -> float:
	var limit := deg_to_rad(LOAD_ROLL_CORRECTION_LIMIT)
	return -right_roll + clampf(left_correction, -limit, limit)


## Declare the combat-aligned projection: the sword's hands `raise` metres
## above the blade plane, level, at every θ and phase.
func configure_projection(aligned: bool, raise_above_plane: float) -> void:
	combat_aligned = aligned
	interaction_raise = raise_above_plane


## Declare this body's charged-cut load: the hands `hands_above_plane` metres
## above the plane, the blade `pitch_degrees` point up, and, if `roll_authored`
## (the declared high guard), the blade's roll at the full wind-back of a right
## load (degrees about the blade axis); the left load is its mirror image (the
## same roll, side-signed, as the shared guard roll is) plus at most
## `LOAD_ROLL_CORRECTION_LIMIT` of right-handed correction
## (`left_correction_degrees`), so both sides are one weapon action. The far
## guard keys are rebuilt from this body's Ready key (call after
## `configure_centre`). The defaults reproduce the shared load exactly.
func configure_load(hands_above_plane: float, pitch_degrees: float, roll_authored: bool = false, roll_degrees: float = 0.0, left_correction_degrees: float = 0.0) -> void:
	_load_raise = hands_above_plane
	_load_pitch = deg_to_rad(pitch_degrees)
	_load_roll_authored = roll_authored
	_load_roll_right = deg_to_rad(roll_degrees)
	_load_roll_left = mirrored_load_roll(_load_roll_right, deg_to_rad(left_correction_degrees))
	_high_raise = _stance_raise.duplicate()
	_high_pitch = _stance_pitch.duplicate()
	for index in STANCE_DEGREES.size():
		var share := high_share(STANCE_DEGREES[index])
		if share > 0.0:
			_high_raise[index] = lerpf(_stance_raise[1], hands_above_plane, share)
			_high_pitch[index] = lerpf(_stance_pitch[1], pitch_degrees, share)


## Declare that this body's long edge leads the motion: the strike region
## `strike_from_carriage` metres beyond the carriage along the blade (the
## centre of percussion for the sword) orients the roll.
func configure_edge(leads: bool, strike_from_carriage: float, cutting_edge: Vector3 = SwordGripFrame.CROSSGUARD_AXIS) -> void:
	_edge_leads = leads
	_edge_radius = strike_from_carriage
	_edge_offset = atan2(cutting_edge.y, cutting_edge.x)


## How far a blade `degrees` round on the attack-origin side has risen from
## Ready toward the high guard (0 at or inside 45°, 1 at 135°), from the shared
## X landmarks.
static func high_share(degrees: float) -> float:
	return clampf((sample_keys(X_HIGH_DEGREES, X_HIGH_HEIGHT, degrees) - X_HIGH_HEIGHT[0]) / (1.0 - X_HIGH_HEIGHT[0]), 0.0, 1.0)


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
	var lift := _lift(angle, phase, cut_dir, committed)
	raise = lift[0]
	pitch = lift[1]
	roll = -side * deg_to_rad(ROLL_DEGREES) * smoothstep(ROLL_START, ROLL_END, degrees)
	if _edge_leads:
		roll = edge_roll(angle, cut_dir, lift, _lift(angle + signf(cut_dir) * EDGE_PROBE_RAD, phase, cut_dir, committed), _edge_radius) - _edge_offset
		## Whole turns only (the pose is unchanged), so the roll stays continuous
		## for any caller that blends it and never spins the long way round.
		if not is_nan(_edge_previous):
			roll = _edge_previous + wrapf(roll - _edge_previous, -PI, PI)
		_edge_previous = roll
	elif _high_side(angle, phase, cut_dir):
		roll = lerpf(roll, _load_roll_right if side < 0.0 else _load_roll_left, high_share(degrees))
	if combat_aligned:
		raise = interaction_raise
		pitch = 0.0
		roll = 0.0
	_angle = angle
	_carriage = Vector2(carriage_left, carriage_forward)
	_blade_height = blade_height
	compose()
	return self


## Whether the declared high guard holds at `angle`: on the blade's own side in
## a guard or a charge, and on the origin side of a cut in flight (never its far
## side).
func _high_side(angle: float, phase: CombatPhase.Id, cut_dir: float) -> bool:
	return _load_roll_authored and (not (is_swing(phase) or phase == CombatPhase.Id.RECOVERY) or signf(angle) == -signf(cut_dir))


## Hands' height above the plane ([0]) and blade pitch ([1], radians) at `angle`
## for the current `stance_weight` and `gather`: the guard keys (the high guard's
## on its side), the cut curve as the swing leaves the stance, and — on bodies
## without a declared high guard — the shared gather lift.
func _lift(angle: float, phase: CombatPhase.Id, cut_dir: float, committed: bool) -> PackedFloat64Array:
	var degrees := rad_to_deg(absf(angle))
	var high := _high_side(angle, phase, cut_dir)
	var stance_raise := sample_keys(STANCE_DEGREES, _high_raise if high else _stance_raise, degrees)
	var stance_pitch := deg_to_rad(sample_keys(STANCE_DEGREES, _high_pitch if high else _stance_pitch, degrees))
	var out := PackedFloat64Array([stance_raise, stance_pitch])
	if stance_weight < 1.0:
		var a := CutPresentationCurve.cut_angle(angle, cut_dir)
		var share := CutPresentationCurve.stance_share(a, committed)
		var cut_raise := lerpf(CutPresentationCurve.raise(a), stance_raise, share)
		var cut_pitch := lerpf(CutPresentationCurve.pitch(a), stance_pitch, share)
		out = PackedFloat64Array([lerpf(cut_raise, stance_raise, stance_weight), lerpf(cut_pitch, stance_pitch, stance_weight)])
	if gather > 0.0 and not _load_roll_authored:
		out = PackedFloat64Array([lerpf(out[0], _load_raise, gather), lerpf(out[1], _load_pitch, gather)])
	return out


## The roll about the blade's own axis that puts the long edge (local +X) on
## the strike region's direction of travel when the blade moves from `angle` in
## the cut direction: the strike region `strike_radius` beyond the carriage at
## `lift` ([raise, pitch]) and at the next probe angle's `next_lift`, its
## displacement taken across the blade, and the roll that turns +X onto it. The
## carriage's own slide is not included (its share of the strike region's
## motion is small against the rotation and the lift); a blade at rest is
## oriented for the cut it would launch.
static func edge_roll(angle: float, cut_dir: float, lift: PackedFloat64Array, next_lift: PackedFloat64Array, strike_radius: float) -> float:
	var next_angle := angle + signf(cut_dir) * EDGE_PROBE_RAD
	var basis := Basis.from_euler(Vector3(-lift[1], angle, 0.0), EULER_ORDER_YXZ)
	var next_basis := Basis.from_euler(Vector3(-next_lift[1], next_angle, 0.0), EULER_ORDER_YXZ)
	var here := Vector3(0.0, lift[0], 0.0) + basis.z * strike_radius
	var there := Vector3(0.0, next_lift[0], 0.0) + next_basis.z * strike_radius
	var travel := there - here
	travel -= basis.z * travel.dot(basis.z)
	return atan2(travel.dot(basis.y), travel.dot(basis.x))


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
