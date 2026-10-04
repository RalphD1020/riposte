class_name ArenaConstraints
extends RefCounted

## Hard circular arena boundary (no ring-outs) and deterministic body
## separation (COMBAT §61). Fighters never share space; blades never block
## bodies.
##
## See also: /docs/concepts/combat.md

const SEPARATION_PASSES := 2


static func resolve(a: FighterState, b: FighterState, rules: DuelRules) -> void:
	for _pass in SEPARATION_PASSES:
		separate(a, b, rules.fighter.body_radius)
		confine(a, rules.arena_radius - rules.fighter.body_radius)
		confine(b, rules.arena_radius - rules.fighter.body_radius)


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


static func separate(a: FighterState, b: FighterState, body_radius: float) -> void:
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
	var push := (min_distance - distance) * 0.5
	a.x -= nx * push
	a.y -= ny * push
	b.x += nx * push
	b.y += ny * push
	var closing := (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
	if closing > 0.0:
		var half := closing * 0.5
		a.vx -= nx * half
		a.vy -= ny * half
		b.vx += nx * half
		b.vy += ny * half
