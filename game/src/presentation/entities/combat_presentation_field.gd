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
##
## The numbers live in the weapon's path data (`WeaponPathDefinition`, the
## reference sword's by default): the guard keys over |θ| (Long Guard lifts the
## hands a little above Ready — higher costs the bladed left arm its Long Guard
## extension, PRES-LONGPOINT-001; wound fully round without a charge the blade
## stays low and shallow under the heroic head, PRES-RIG), the shared gather
## load, the stance / descent progress windows, the shared X projection's
## normalized heights on the attack-origin side (Ready 0.75, gather 0.88, full
## wind-back 1.00; the share toward a declared high guard is
## `(height − 0.75) / 0.25`) and the side-signed crossguard roll.

## The angular step over which the strike region's direction of travel is read
## when the long edge leads the motion.
const EDGE_PROBE_RAD := deg_to_rad(0.5)

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

## The body's declared drawing and the weapon's path data in it. Read once, at
## construction; never written by the field.
var config: WeaponPresentationConfig
var path: WeaponPathDefinition = WeaponPathDefinition.reference_sword()

var _angle: float = 0.0
var _carriage := Vector2.ZERO
var _blade_height: float = 0.0
## This field's guard keys: the path's tables unless the body declares a
## different centre (`WeaponPresentationConfig.with_centre`).
var _stance_raise: PackedFloat64Array = path.stance_raise
var _stance_pitch: PackedFloat64Array = path.stance_pitch_degrees
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
## (`WeaponPresentationConfig.with_load(..., true, ...)`) the lift is angle-driven by the shared X
## projection instead of gather-driven: on the attack-origin side the guard keys
## at 90° and 135° rise from Ready toward the high guard (`_high_raise` /
## `_high_pitch`) and the blade rolls about its own axis toward that side's
## roll (θ < 0 the right load) by the same share — one continuous angle, so the
## crossguard never jumps through another orientation — and a charge adds no
## lift of its own (where the blade is decides how high it is drawn). The far
## side of a cut keeps the shared low lift. The shared constants, gather lift
## and side-signed guard roll on every shipping body.
var _load_raise: float = path.load_raise
var _load_pitch: float = deg_to_rad(path.load_pitch_degrees)
var _load_roll_authored: bool = false
var _load_roll_right: float = 0.0
var _high_raise: PackedFloat64Array = path.stance_raise
var _high_pitch: PackedFloat64Array = path.stance_pitch_degrees
## The long edge leads the motion (a body's declared choice, `with_edge`):
## the blade's roll is derived each sample from the strike region's direction of
## travel in the cut direction (`edge_roll`) instead of the side-signed guard
## roll and the high guard's authored rolls, so the same edge leads through the
## load, the descent, the centre and the follow-through of both diagonals.
## Off on every shipping body.
var _edge_leads: bool = false
var _edge_radius: float = 0.0
## The cutting edge's angle from +X in the sword frame (0 for edge A, π for B).
var _edge_offset: float = 0.0


## The body's declared drawing (`WeaponPresentationConfig`; the reference
## sword's defaults when null), from which every table is derived once:
##
## - its Long Guard key: the centre's hand height and blade pitch moved by the
##   declared deltas, eased into the unchanged Ready key like any other (zero
##   deltas are the shared tables exactly);
## - the combat-aligned projection: the hands `interaction_raise` above the
##   plane, level, at every θ and phase;
## - its charged-cut load: the hands' height and the blade's pitch at the full
##   wind-back and, for a declared high guard, the right load's roll about the
##   blade (the left load is its exact mirror image — the weapon's path has no
##   side, only the grip does). The far guard keys are rebuilt from this body's
##   Ready key;
## - whether the long edge leads: the strike region (the centre of percussion)
##   orients the roll.
func _init(declared: WeaponPresentationConfig = null) -> void:
	config = declared if declared != null else WeaponPresentationConfig.shared()
	path = config.path
	carriage_radius = config.carriage_radius
	_stance_raise = path.stance_raise.duplicate()
	_stance_pitch = path.stance_pitch_degrees.duplicate()
	_stance_raise[0] += config.centre_raise_delta
	_stance_pitch[0] += config.centre_pitch_delta_degrees
	combat_aligned = config.combat_aligned
	interaction_raise = config.interaction_raise
	_load_raise = path.load_raise if is_nan(config.load_raise) else config.load_raise
	var load_pitch_degrees := path.load_pitch_degrees if is_nan(config.load_pitch_degrees) else config.load_pitch_degrees
	_load_pitch = deg_to_rad(load_pitch_degrees)
	_load_roll_authored = config.load_roll_authored
	_load_roll_right = deg_to_rad(config.load_roll_degrees)
	_high_raise = _stance_raise.duplicate()
	_high_pitch = _stance_pitch.duplicate()
	for index in path.stance_degrees.size():
		var share := high_share(path.stance_degrees[index], path)
		if share > 0.0:
			_high_raise[index] = lerpf(_stance_raise[1], _load_raise, share)
			_high_pitch[index] = lerpf(_stance_pitch[1], load_pitch_degrees, share)
	_edge_leads = config.edge_leads
	_edge_radius = config.edge_strike_from_carriage
	_edge_offset = atan2(config.cutting_edge.y, config.cutting_edge.x)


## How far a blade `degrees` round on the attack-origin side has risen from
## Ready toward the high guard (0 at or inside 45°, 1 at 135°), from the shared
## X landmarks of `path_data` (the reference sword's by default).
static func high_share(degrees: float, path_data: WeaponPathDefinition = null) -> float:
	var p := path_data if path_data != null else WeaponPathDefinition.reference_sword()
	return clampf((sample_keys(p.x_high_degrees, p.x_high_height, degrees) - p.x_high_height[0]) / (1.0 - p.x_high_height[0]), 0.0, 1.0)


## Lift the authoritative sword at `angle` (relative weapon angle θ) whose
## carriage sits `carriage_left` / `carriage_forward` in the combat frame, for
## `phase` at `progress` through the swing; `charge` is the hold's earned
## charge, `swing_charge` the charge the swing in flight was launched with;
## `blade_height` is the authoritative plane's height. Pure: the same inputs
## always give the same pose.
func sample(angle: float, carriage_left: float, carriage_forward: float, phase: CombatPhase.Id, progress: float, charge: float, swing_charge: float, blade_height: float, cut_dir: float = 1.0, committed: bool = false) -> CombatPresentationField:
	var degrees := rad_to_deg(absf(angle))
	var side := signf(angle)
	stance_weight = stance_weight_for(phase, progress, path)
	gather = gather_for(phase, progress, charge, swing_charge, path)
	var lift := _lift(angle, phase, cut_dir, committed)
	raise = lift[0]
	pitch = lift[1]
	roll = -side * deg_to_rad(path.roll_degrees) * smoothstep(path.roll_start, path.roll_end, degrees)
	if _edge_leads:
		## Principal value: a caller that blends rolls wraps their difference.
		roll = wrapf(edge_roll(angle, cut_dir, lift, _lift(angle + signf(cut_dir) * EDGE_PROBE_RAD, phase, cut_dir, committed), _edge_radius) - _edge_offset, -PI, PI)
	elif _high_side(angle, phase, cut_dir):
		roll = lerpf(roll, -side * _load_roll_right, high_share(degrees, path))
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
	var stance_raise := sample_keys(path.stance_degrees, _high_raise if high else _stance_raise, degrees)
	var stance_pitch := deg_to_rad(sample_keys(path.stance_degrees, _high_pitch if high else _stance_pitch, degrees))
	var out := PackedFloat64Array([stance_raise, stance_pitch])
	if stance_weight < 1.0:
		var a := CutPresentationCurve.cut_angle(angle, cut_dir)
		var share := CutPresentationCurve.stance_share(a, committed, path)
		var cut_raise := lerpf(CutPresentationCurve.raise(a, path), stance_raise, share)
		var cut_pitch := lerpf(CutPresentationCurve.pitch(a, path), stance_pitch, share)
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
static func stance_weight_for(phase: CombatPhase.Id, progress: float, path_data: WeaponPathDefinition = null) -> float:
	var p := path_data if path_data != null else WeaponPathDefinition.reference_sword()
	if phase == CombatPhase.Id.RECOVERY:
		return 0.0
	if not is_swing(phase):
		return 1.0
	return 1.0 - smoothstep(0.0, p.leave_stance_end, clampf(progress, 0.0, 1.0))


## How far toward the high shoulder load the sword is gathered: the earned
## charge while holding (point height is the charge cue), and the launch charge
## coming down off the shoulder over the first part of the swing's travel.
static func gather_for(phase: CombatPhase.Id, progress: float, charge: float, swing_charge: float, path_data: WeaponPathDefinition = null) -> float:
	var p := path_data if path_data != null else WeaponPathDefinition.reference_sword()
	if phase == CombatPhase.Id.CHARGING:
		return clampf(charge, 0.0, 1.0)
	if is_swing(phase):
		return clampf(swing_charge, 0.0, 1.0) * (1.0 - smoothstep(0.0, p.descent_end, clampf(progress, 0.0, 1.0)))
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
