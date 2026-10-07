class_name ArenaConstraints
extends RefCounted

## Open circular arena with deterministic body separation (COMBAT §61). The
## arena has no hard wall — crossing the edge triggers a ring-out.
## Fighters never share space; blades never block bodies. Separation is
## mass-aware: a heavier fighter absorbs less of the push and less of the
## closing velocity (PHYS-005).
##
## See also: /docs/concepts/combat.md

const SEPARATION_PASSES := 2


## Resolve body separation for two non-falling, alive fighters. No confinement
## — the arena edge is open and crossing it triggers a ring-out elsewhere.
static func resolve(a: FighterState, b: FighterState, rules: DuelRules) -> void:
	if a.is_falling or b.is_falling:
		return
	var mass := rules.fighter.mass
	for _pass in SEPARATION_PASSES:
		separate(a, b, rules.fighter.body_radius, mass, mass)


## Swept point-circle edge crossing. Given a center that linearly interpolates
## from (sx, sy) to (fx, fy), returns the smallest fraction t ∈ (0, 1] where
## |P(t)| = radius, or -1.0 if the center never exits. Solves the quadratic
## |P_start + t × ΔP|² = R².
static func detect_edge_crossing(sx: float, sy: float, fx: float, fy: float, radius: float) -> float:
	var dx := fx - sx
	var dy := fy - sy
	var a := dx * dx + dy * dy
	if a < SimMath.EPSILON:
		return -1.0
	var b := 2.0 * (sx * dx + sy * dy)
	var c := sx * sx + sy * sy - radius * radius
	if c >= 0.0:
		return -1.0
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return -1.0
	var sqrt_disc := sqrt(disc)
	var t := (-b + sqrt_disc) / (2.0 * a)
	if t > 0.0 and t <= 1.0:
		return t
	return -1.0


## Push two overlapping bodies apart along the line between them.
##
## Position correction and velocity correction both use inverse-mass
## weighting, so a heavier fighter moves less (PHYS-005). The arena has no
## wall: separation is purely physical and may push a fighter past the
## platform edge, producing a ring-out.
static func separate(a: FighterState, b: FighterState, body_radius: float, mass_a: float = 1.0, mass_b: float = 1.0) -> void:
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
	var inv_total := 1.0 / mass_a + 1.0 / mass_b
	var share_a := (1.0 / mass_a) / inv_total if inv_total > SimMath.EPSILON else 0.5
	var share_b := 1.0 - share_a
	a.x -= nx * overlap * share_a
	a.y -= ny * overlap * share_a
	b.x += nx * overlap * share_b
	b.y += ny * overlap * share_b
	var closing := (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
	if closing > 0.0:
		var delta_a := closing * share_a
		var delta_b := closing * share_b
		a.vx -= nx * delta_a
		a.vy -= ny * delta_a
		b.vx += nx * delta_b
		b.vy += ny * delta_b
