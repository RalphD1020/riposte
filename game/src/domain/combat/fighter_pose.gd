class_name FighterPose
extends RefCounted

## A fighter's spatial pose at one instant: center, facing, relative weapon
## angle, and the absolute blade direction as a unit vector. Captured before
## and after integration so collision can sweep the motion between them.
##
## See also: /docs/concepts/combat.md

var x: float = 0.0
var y: float = 0.0
var facing: float = 0.0
var weapon_angle: float = 0.0
var blade_angle: float = 0.0
var ux: float = 1.0
var uy: float = 0.0


static func capture(fighter: FighterState) -> FighterPose:
	var pose := FighterPose.new()
	pose.write(fighter)
	return pose


func write(fighter: FighterState) -> void:
	x = fighter.x
	y = fighter.y
	facing = fighter.facing
	weapon_angle = fighter.weapon.angle
	blade_angle = DuelGeometry.blade_angle(fighter)
	ux = SimMath.cosine(blade_angle)
	uy = SimMath.sine(blade_angle)
