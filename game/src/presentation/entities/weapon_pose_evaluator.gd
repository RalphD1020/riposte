class_name WeaponPoseEvaluator
extends RefCounted
## WEAPON-PATH-004: the one evaluation of the drawn weapon. From the
## authoritative planar sword (`WeaponKinematics` at the interpolated θ), the
## action in flight (`WeaponActionContext`), the body's declared drawing
## (`WeaponPresentationConfig`, its path data inside) and the declared visual
## carry, it gives the rigid weapon transform, its stations (grips, guard root,
## blade root, tip, centre of mass, centre of percussion), both hands' full
## grip transforms (`T_hand = T_weapon · G`) and the wrists they imply, and —
## on demand — how any station moves per radian of θ. Pure: the same inputs
## always give the same bits; nothing is written back and nothing is
## remembered between evaluations. The drawn sword, the hands' targets and
## any audit query read this one result; nothing else decides where the
## weapon is drawn.
##
## Combat frame (the fighter's VisualRoot): +X the fighter's left, +Y up, +Z
## forward. Sword frame: origin at the pommel, +Z down the blade, +X the
## crossguard bar, +Y the flat's normal.
##
## Implements: /spec/invariants.md#weapon-path-004
## See also: /docs/concepts/presentation.md

## The step of the central difference for station rates (rad).
const RATE_STEP_RAD := 1.0e-4

var config: WeaponPresentationConfig
## The path's lift (height, pitch, roll over the planar sword).
var field: CombatPresentationField
## Results of the last `evaluate`, in the combat frame. Preallocated.
var weapon := Transform3D.IDENTITY
var carriage_point := Vector3.ZERO
## The lift as drawn: hands' height above the plane, pitch, roll.
var lift := Vector3.ZERO
## The Hand bones' wanted transforms and the wrists the arms reach (index 0
## the dominant / right hand). Identity / zero while the body holds no grips.
var grips: Array[Transform3D] = [Transform3D.IDENTITY, Transform3D.IDENTITY]
var wrists := PackedVector3Array([Vector3.ZERO, Vector3.ZERO])

var _spec: CombatantPhysicsSpec
var _twin: WeaponPoseEvaluator
var _rate_planar := BladePose.new()


func _init(spec: CombatantPhysicsSpec, declared: WeaponPresentationConfig = null) -> void:
	_spec = spec
	config = declared if declared != null else WeaponPresentationConfig.shared().with_carriage_radius(spec.handling.carriage_radius)
	field = CombatPresentationField.new(config)


## Evaluate the weapon on `planar` (the authoritative sword posed at `angle`)
## for `context`, the blade plane at `blade_height`, with the declared visual
## `carry` (height, pitch, roll) added to the lift. A sword contact is not an
## input: the drawn sword stays continuous through it
## (CONTACT-PRESENTATION-001). Returns self.
func evaluate(planar: BladePose, angle: float, blade_height: float, context: WeaponActionContext, carry: Vector3 = Vector3.ZERO) -> WeaponPoseEvaluator:
	field.sample(angle, planar.carriage_y, planar.carriage_x, context.phase, context.progress, context.charge, context.swing_charge, blade_height, context.cut_dir, context.committed)
	field.raise += carry.x
	field.pitch += carry.y
	field.roll += carry.z
	field.compose()
	weapon = field.transform
	carriage_point = field.carriage_point
	lift = Vector3(field.raise, field.pitch, field.roll)
	if config.has_grips():
		for index in 2:
			grips[index] = weapon * config.grip_frames[index]
			wrists[index] = grips[index] * config.grip_wrists[index]
	return self


## The point `radius` metres down the blade from the pommel, combat frame.
func station(radius: float) -> Vector3:
	return weapon * Vector3(0.0, 0.0, radius)


## The sword's own frame moved to the station `radius` down the blade.
func station_frame(radius: float) -> Transform3D:
	return Transform3D(weapon.basis, station(radius))


func tip() -> Vector3:
	return station(_spec.weapon.tip_radius)


func blade_root() -> Vector3:
	return station(_spec.weapon.blade_base_radius)


## The crossguard's centre: the guard root.
func guard_root() -> Vector3:
	return station(_spec.weapon.crossguard_centre_radius)


## One end of the crossguard bar (`side` +1 along the sword's +X, −1 along −X).
func crossguard_end(side: float) -> Vector3:
	return weapon * Vector3(signf(side) * _spec.weapon.crossguard_half_span, 0.0, _spec.weapon.crossguard_centre_radius)


func centre_of_mass() -> Vector3:
	return station(_spec.weapon.center_of_mass_radius)


## The strike region the long edge is oriented by (the body's declared centre
## of percussion, beyond the carriage).
func centre_of_percussion() -> Vector3:
	return station(config.carriage_radius + config.edge_strike_from_carriage)


## Where a region of the weapon (`WeaponStationTopology`) lies: its two ends on
## the drawn axis, combat frame.
func region_ends(region: WeaponStationTopology.Region) -> PackedVector3Array:
	return PackedVector3Array([station(region.from_radius), station(region.to_radius)])


## The guard root's corners (GUARD-PROTECTION-001): the bar's two ends and the
## apex, combat frame. Empty for a sword with no crossguard.
func guard_root_corners() -> PackedVector3Array:
	if _spec.weapon.crossguard_half_span <= 0.0:
		return PackedVector3Array()
	return PackedVector3Array([crossguard_end(1.0), crossguard_end(-1.0), station(_spec.weapon.guard_root_apex_radius())])


## Where hand `index`'s palm holds the handle, combat frame.
func grip_station(index: int) -> Vector3:
	return weapon * config.grip_stations[index]


## How the station `radius` down the blade moves per radian of θ at `angle`
## for `context` (central difference over the same evaluation; the result of
## the last `evaluate` is untouched). Undefined across a branch boundary.
func station_rate(angle: float, blade_height: float, context: WeaponActionContext, radius: float, carry: Vector3 = Vector3.ZERO) -> Vector3:
	var twin := _rate_twin()
	WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle + RATE_STEP_RAD, _spec, _rate_planar)
	var ahead := twin.evaluate(_rate_planar, angle + RATE_STEP_RAD, blade_height, context, carry).station(radius)
	WeaponKinematics.pose_at(0.0, 0.0, 0.0, angle - RATE_STEP_RAD, _spec, _rate_planar)
	var behind := twin.evaluate(_rate_planar, angle - RATE_STEP_RAD, blade_height, context, carry).station(radius)
	return (ahead - behind) / (2.0 * RATE_STEP_RAD)


func _rate_twin() -> WeaponPoseEvaluator:
	if _twin == null:
		_twin = WeaponPoseEvaluator.new(_spec, config)
	return _twin
