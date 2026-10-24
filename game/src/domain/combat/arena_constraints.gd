class_name ArenaConstraints
extends RefCounted

## Circular arena with deterministic body separation (COMBAT §61). An open
## edge has no wall: crossing it triggers a ring-out. A closed edge holds the
## centre at the support radius instead.
## Fighters never share space; blades never block bodies. Separation is
## mass-aware: a heavier fighter absorbs less of the push and less of the
## closing velocity (PHYS-005).
##
## Body/body velocity response has one law and one mass (BODY-CONTACT-OWNERSHIP-001):
## `ContactResolver` resolves the contact in the tick's chronology, and the
## closing speed removed here is that same zero-restitution law with the same
## `fighter.mass`, for a re-overlap later in the tick that the resolver has not
## seen. The persistent sword solver keeps bodies apart by position only.
##
## See also: /docs/concepts/combat.md

const SEPARATION_PASSES := 2
## How far outside touching (m) a separated pair is left: numerical
## hysteresis separating the resting configuration from the contact trigger,
## not game-world physics. Contact is detected at exactly touching; resting
## exactly there would let rounding decide whether the next tick sees a
## contact, and mirrored scenes would diverge. The contract (tested): far
## above the ULP of the authoritative 64-bit positions at arena scale, far
## below anything visible and the sword `contact_slop`, mirrored contacts
## exact, a long hold stable. Its value is part of the rules: changing it moves
## every replay that ever separates two bodies.
const BODY_CONTACT_REST_EPSILON := 1.0e-9


## Resolve body separation for two non-falling, alive fighters. An open edge
## does not confine them. A closed edge pulls any centre the separation
## pushed past the support radius back onto it.
static func resolve(a: FighterState, b: FighterState, rules: DuelRules) -> void:
	if a.is_falling or b.is_falling:
		return
	var body_a := rules.spec_of(a).fighter
	var body_b := rules.spec_of(b).fighter
	for _pass in SEPARATION_PASSES:
		separate(a, b, body_a.push_radius, body_b.push_radius, body_a.mass, body_b.mass)
	if rules.is_closed_edge():
		constrain(a, rules)
		constrain(b, rules)
		separate(a, b, body_a.push_radius, body_b.push_radius, body_a.mass, body_b.mass)
		constrain(a, rules)
		constrain(b, rules)


## Hold a living or settled centre on a closed edge. A standing fighter is
## inset by `push_radius`. A body is inset by its lying half-length, because
## the capsule is longer than the standing circle. Outward radial speed is
## removed only when the centre is on that circle, in the same tick it is
## pulled back. Inside the circle the movement system owns the velocity.
## An open edge is left untouched, and a fighter who has already lost
## support is left on the fall.
static func support_limit(fighter: FighterState, rules: DuelRules) -> float:
	var body := rules.spec_of(fighter).fighter
	var inset := body.push_radius
	if fighter.fallen.active:
		inset = maxf(inset, body.lying_half_length)
	return rules.platform_radius - inset


static func constrain(fighter: FighterState, rules: DuelRules) -> void:
	if not rules.is_closed_edge() or fighter.is_falling:
		return
	var limit := support_limit(fighter, rules)
	if limit <= SimMath.EPSILON:
		return
	var dist := SimMath.length(fighter.x, fighter.y)
	if dist > limit:
		var scale := limit / dist
		fighter.x *= scale
		fighter.y *= scale
		dist = limit
	## A wall stops you at the stone. It does not delete a retreat in the middle.
	if dist + SimMath.EPSILON < limit or dist <= SimMath.EPSILON:
		return
	var nx := fighter.x / dist
	var ny := fighter.y / dist
	var radial := fighter.vx * nx + fighter.vy * ny
	if radial > 0.0:
		fighter.vx -= radial * nx
		fighter.vy -= radial * ny


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
## platform edge, producing a ring-out. The bodies touch at the sum of their
## own push radii.
static func separate(a: FighterState, b: FighterState, push_radius_a: float, push_radius_b: float, mass_a: float, mass_b: float) -> void:
	var min_distance := push_radius_a + push_radius_b
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
	var overlap := min_distance + BODY_CONTACT_REST_EPSILON - distance
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
