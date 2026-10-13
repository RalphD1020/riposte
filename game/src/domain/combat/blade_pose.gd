class_name BladePose
extends RefCounted

## One fighter's rigid sword at one instant, in world space: where its carriage
## (grip centre) and origin (pommel) are, which way the blade points, and how
## the origin moves per radian of weapon angle. Written by `WeaponKinematics`;
## callers keep one and reuse it, so geometry queries allocate nothing.
##
## See also: /docs/concepts/combat.md

## World position of the origin (the pommel), where every blade radius starts.
var origin_x: float = 0.0
var origin_y: float = 0.0
## Origin minus the fighter's centre (world).
var offset_x: float = 0.0
var offset_y: float = 0.0
## World carriage (grip centre) position.
var carriage_x: float = 0.0
var carriage_y: float = 0.0
## Unit blade direction (world): yaw = combat heading + weapon angle.
var ux: float = 1.0
var uy: float = 0.0
## d(origin)/dθ in world axes.
var dorigin_x: float = 0.0
var dorigin_y: float = 0.0
## The track sample in the combat frame: the carriage (forward / left) and its
## rate per radian of θ.
var carriage_forward: float = 0.0
var carriage_left: float = 0.0
var d_carriage_forward: float = 0.0
var d_carriage_left: float = 0.0
## Scratch result of `WeaponKinematics.velocity_into`.
var vx: float = 0.0
var vy: float = 0.0


## World point `r` metres down the blade from the origin.
func point_x(r: float) -> float:
	return origin_x + ux * r


func point_y(r: float) -> float:
	return origin_y + uy * r
