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


## Unit vector from `fighter` toward where `opponent` actually is, which is
## the axis footwork is expressed in: W closes, S retreats, A and D orbit.
##
## This is the opponent's *bearing*, not the fighter's body facing. Using
## facing would make movement swing around with a turning torso, so a fighter
## mid-recovery would walk off at an angle they never asked for.
##
## Two fighters can end up effectively on top of each other, where the bearing
## is numerically meaningless. Rather than invent a direction, the caller's
## last known heading is returned, so footwork at zero separation stays
## continuous instead of snapping.
static func duel_basis(fighter: FighterState, opponent: FighterState, fallback_x: float, fallback_y: float) -> PackedFloat64Array:
	var dx := opponent.x - fighter.x
	var dy := opponent.y - fighter.y
	var length := SimMath.length(dx, dy)
	if length <= SimMath.EPSILON:
		return PackedFloat64Array([fallback_x, fallback_y])
	return PackedFloat64Array([dx / length, dy / length])


## Rotate a duel-relative intent (`+y` forward, `+x` right) into world axes.
##
## Right is the forward axis turned a quarter turn clockwise, which is what
## makes local D project right on screen for both sides once the camera puts
## the local fighter at the bottom.
static func to_world(intent_x: float, intent_y: float, forward_x: float, forward_y: float) -> PackedFloat64Array:
	return PackedFloat64Array([
		intent_x * forward_y + intent_y * forward_x,
		intent_y * forward_y - intent_x * forward_x,
	])


## The exact inverse of `to_world`: express a world vector in duel axes.
## Controllers that think geometrically (the CPU) use this so they still speak
## the same command language a human's keyboard does.
static func to_duel(world_x: float, world_y: float, forward_x: float, forward_y: float) -> PackedFloat64Array:
	return PackedFloat64Array([
		world_x * forward_y - world_y * forward_x,
		world_x * forward_x + world_y * forward_y,
	])


## Absolute blade angle (facing + relative sword angle).
static func blade_angle(fighter: FighterState) -> float:
	return SimMath.wrap_angle(fighter.facing + fighter.weapon.angle)
