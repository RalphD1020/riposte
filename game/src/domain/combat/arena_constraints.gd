class_name ArenaConstraints
extends RefCounted

## Hard circular arena boundary (no ring-outs) and deterministic body
## separation (COMBAT §61). Fighters never share space; blades never block
## bodies. Separation is mass-aware: a heavier fighter absorbs less of the
## push and less of the closing velocity (PHYS-005).
##
## See also: /docs/concepts/combat.md

const SEPARATION_PASSES := 2


static func resolve(a: FighterState, b: FighterState, rules: DuelRules) -> void:
	var limit := rules.arena_radius - rules.fighter.body_radius
	var mass := rules.fighter.mass
	for _pass in SEPARATION_PASSES:
		separate(a, b, rules.fighter.body_radius, limit, mass, mass)
		confine(a, limit)
		confine(b, limit)


static func confine(fighter: FighterState, limit: float) -> void:
	var distance := SimMath.length(fighter.x, fighter.y)
	if distance <= limit or distance <= SimMath.EPSILON:
		return
	var nx := fighter.x / distance
	var ny := fighter.y / distance
	fighter.x = nx * limit
	fighter.y = ny * limit
	var outward := fighter.vx * nx + fighter.vy * ny
	if outward > 0.0:
		fighter.vx -= outward * nx
		fighter.vy -= outward * ny


## Push two overlapping bodies apart along the line between them.
##
## Position correction and velocity correction both use inverse-mass
## weighting, so a heavier fighter moves less (PHYS-005). Wall proximity
## still overrides: a body already against the wall has nowhere to go,
## and the other must absorb the whole separation.
static func separate(a: FighterState, b: FighterState, body_radius: float, limit: float, mass_a: float = 1.0, mass_b: float = 1.0) -> void:
	var min_distance := body_radius * 2.0
	var dx := b.x - a.x
	var dy := b.y - a.y
	var distance := SimMath.length(dx, dy)
	if distance >= min_distance:
		return
	var nx := 1.0
	var ny := 0.0
	if distance > SimMath.EPSILON:
		nx = dx / distance
		ny = dy / distance
	var overlap := min_distance - distance
	var room_a := SimMath.ray_exit_distance(a.x, a.y, -nx, -ny, limit)
	var room_b := SimMath.ray_exit_distance(b.x, b.y, nx, ny, limit)
	var inv_total := 1.0 / mass_a + 1.0 / mass_b
	var share_a := (1.0 / mass_a) / inv_total if inv_total > SimMath.EPSILON else 0.5
	var share_b := 1.0 - share_a
	var push_a := minf(overlap * share_a, room_a)
	var push_b := minf(overlap * share_b, room_b)
	push_a += minf(overlap - push_a - push_b, room_a - push_a)
	push_b += minf(overlap - push_a - push_b, room_b - push_b)
	a.x -= nx * push_a
	a.y -= ny * push_a
	b.x += nx * push_b
	b.y += ny * push_b
	var closing := (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
	if closing > 0.0:
		var delta_a := closing * share_a
		var delta_b := closing * share_b
		a.vx -= nx * delta_a
		a.vy -= ny * delta_a
		b.vx += nx * delta_b
		b.vy += ny * delta_b
