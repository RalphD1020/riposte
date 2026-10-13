class_name FighterPose
extends RefCounted

## A fighter's spatial pose at one instant: center, facing, relative weapon
## angle, the sword's origin (from `WeaponKinematics`), and the absolute blade
## direction as a unit vector. Captured before and after integration so
## collision can sweep the motion between them.
##
## See also: /docs/concepts/combat.md

var x: float = 0.0
var y: float = 0.0
var facing: float = 0.0
var weapon_angle: float = 0.0
var blade_angle: float = 0.0
var origin_x: float = 0.0
var origin_y: float = 0.0
## The carriage (grip centre) the attack track places.
var carriage_x: float = 0.0
var carriage_y: float = 0.0
var ux: float = 1.0
var uy: float = 0.0
var _blade := BladePose.new()


static func capture(fighter: FighterState, spec: CombatantPhysicsSpec) -> FighterPose:
	var pose := FighterPose.new()
	pose.write(fighter, spec)
	return pose


func write(fighter: FighterState, spec: CombatantPhysicsSpec) -> void:
	x = fighter.x
	y = fighter.y
	facing = fighter.facing
	weapon_angle = fighter.weapon.angle
	blade_angle = DuelGeometry.blade_angle(fighter)
	WeaponKinematics.pose_of(fighter, spec, _blade)
	origin_x = _blade.origin_x
	origin_y = _blade.origin_y
	carriage_x = _blade.carriage_x
	carriage_y = _blade.carriage_y
	ux = _blade.ux
	uy = _blade.uy
