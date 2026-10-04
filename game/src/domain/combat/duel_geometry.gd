class_name DuelGeometry
extends RefCounted

## Relational geometry between the two fighters (COMBAT §6, §25, §28).
## Meaningful combat is evaluated from the relationship, never one fighter
## alone. Pure functions over scalar state.
##
## See also: /docs/concepts/combat.md


static func distance(a: FighterState, b: FighterState) -> float:
	return SimMath.length(b.x - a.x, b.y - a.y)


## World bearing from `from` toward `to`.
static func bearing(from: FighterState, to: FighterState) -> float:
	return SimMath.arctan2(to.y - from.y, to.x - from.x)


## Signed angle from `from`'s facing to `to` (0 = dead ahead, ±PI = behind).
static func facing_error(from: FighterState, to: FighterState) -> float:
	return SimMath.wrap_angle(bearing(from, to) - from.facing)


## Rate at which `other` orbits around `center` (rad/s, + = counter-clockwise).
static func orbit_rate(center: FighterState, other: FighterState) -> float:
	var rx := other.x - center.x
	var ry := other.y - center.y
	var distance_sq := rx * rx + ry * ry
	if distance_sq <= SimMath.EPSILON:
		return 0.0
	var vrx := other.vx - center.vx
	var vry := other.vy - center.vy
	return (rx * vry - ry * vrx) / distance_sq


## Closing speed along the line between fighters (+ = approaching).
static func closing_speed(a: FighterState, b: FighterState) -> float:
	var dx := b.x - a.x
	var dy := b.y - a.y
	var length := SimMath.length(dx, dy)
	if length <= SimMath.EPSILON:
		return 0.0
	return -((b.vx - a.vx) * dx + (b.vy - a.vy) * dy) / length


## Absolute blade angle (facing + relative sword angle).
static func blade_angle(fighter: FighterState) -> float:
	return SimMath.wrap_angle(fighter.facing + fighter.weapon.angle)
