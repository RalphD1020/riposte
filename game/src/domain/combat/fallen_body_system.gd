class_name FallenBodySystem
extends RefCounted

## How a killed body moves once its round is decided (Phase 15,
## `FallenBodyState`). The same physics as everything else: real mass, an
## inertia derived from its own shape, one contact impulse through one
## effective mass, and Coulomb friction — never a scripted shove or roll.
##
## - A collapse is the centre of mass falling: over its last
##   `fallen_settle_ticks_cut` ticks it travels half the body's length along
##   the lying axis, from above the feet to the lying torso (`collapse`).
## - A body slides on the floor: its speed falls by `μ·g` per second (a
##   standing fighter's braking is a motor, and a body has none, so it is far
##   easier to move), and its spin by that friction's torque over a uniform rod
##   (`α = 1.5·μ·g / h`, derived).
## - A living fighter's push circle meeting a lying body is one normal impulse
##   at the closest point of the body's capsule, through
##   `k = 1/m_a + 1/m_b + (r × n)² / I`, so a push near one end turns it about
##   its centre of mass (`Δω = −J·(r × n) / I`). Inelastic: nothing bounces.
##   Overlap is then cleared along the normal, split by inverse mass.
## - Its centre of mass crossing the platform edge (swept, like a ring-out) is
##   the post-round corpse fall: `over_edge`, one event, and the result of the
##   round untouched. It is never `is_falling` — that is a living fighter's
##   lost footing, and reusing it would rewrite how the round ended.
##
## See also: /docs/concepts/simulation.md

## Gravity at the arena floor (m/s²).
const GRAVITY := 9.81


## Inertia of a lying body about its centre of mass: a uniform rod of the
## body's own length and mass (`m·(2h)²/12`).
static func inertia(body: FighterDefinition) -> float:
	var length := 2.0 * body.lying_half_length
	return body.mass * length * length / 12.0


## One tick of a body sliding on the floor; reports the corpse fall.
static func step(fighter: FighterState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var fallen := fighter.fallen
	var half_length := rules.spec_of(fighter).fighter.lying_half_length
	var dt := SimulationTimebase.TICK_SECONDS
	fighter.gesture.reset()
	var start_x := fighter.x
	var start_y := fighter.y
	if fallen.settle_left > 0:
		## Collapsing: over the last `fallen_settle_ticks_cut` ticks (all of a
		## cut's, the end of a run-through's) the centre of mass travels from
		## above the feet to the lying torso, half the body's length along the
		## lying axis — a fall is the centre of mass going somewhere.
		var collapse := rules.combat.fallen_settle_ticks_cut
		if collapse > 0 and fallen.settle_left <= collapse:
			var step_along := half_length / float(collapse)
			fighter.x += SimMath.cosine(fallen.yaw) * step_along
			fighter.y += SimMath.sine(fallen.yaw) * step_along
		fallen.settle_left -= 1
	var old_vx := fighter.vx
	var old_vy := fighter.vy
	if not fallen.over_edge:
		var friction := rules.combat.fallen_ground_friction * GRAVITY
		var speed := fighter.speed()
		if speed > SimMath.EPSILON:
			var scale := maxf(speed - friction * dt, 0.0) / speed
			fighter.vx *= scale
			fighter.vy *= scale
		var turn_friction := 1.5 * friction / half_length
		fallen.spin = SimMath.approach(fallen.spin, 0.0, turn_friction * dt)
	fighter.ax = (fighter.vx - old_vx) / dt
	fighter.ay = (fighter.vy - old_vy) / dt
	fighter.x += fighter.vx * dt
	fighter.y += fighter.vy * dt
	fighter.turn_rate = 0.0
	fallen.yaw = SimMath.wrap_angle(fallen.yaw + fallen.spin * dt)
	if fallen.over_edge:
		return
	var crossing := ArenaConstraints.detect_edge_crossing(start_x, start_y, fighter.x, fighter.y, rules.platform_radius)
	if crossing >= 0.0:
		fallen.over_edge = true
		events.append(DuelEvent.create(DuelEventTypes.POST_ROUND_CORPSE_FALL, tick, fighter.slot, DuelEvent.NONE, {
			DuelEventKeys.TOI: crossing,
			DuelEventKeys.X: fighter.x,
			DuelEventKeys.Y: fighter.y,
		}))


## The two bodies of a decided round meeting: a lying body is a capsule, any
## other is the standing push circle (`ArenaConstraints`). Bodies off the
## platform meet nothing.
static func resolve_bodies(a: FighterState, b: FighterState, rules: DuelRules) -> void:
	if a.is_falling or b.is_falling or a.fallen.over_edge or b.fallen.over_edge:
		return
	if a.fallen.is_lying() and b.fallen.is_lying():
		return
	if b.fallen.is_lying():
		collide(a, b, rules)
	elif a.fallen.is_lying():
		collide(b, a, rules)
	else:
		ArenaConstraints.resolve(a, b, rules)


## A standing body's push circle against a lying body's capsule.
static func collide(standing: FighterState, body: FighterState, rules: DuelRules) -> void:
	var standing_body := rules.spec_of(standing).fighter
	var lying_body := rules.spec_of(body).fighter
	var ux := SimMath.cosine(body.fallen.yaw)
	var uy := SimMath.sine(body.fallen.yaw)
	var h := lying_body.lying_half_length
	var t := SimMath.closest_param_on_segment(body.x - ux * h, body.y - uy * h, body.x + ux * h, body.y + uy * h, standing.x, standing.y)
	var along := (2.0 * t - 1.0) * h
	var px := body.x + ux * along
	var py := body.y + uy * along
	var dx := standing.x - px
	var dy := standing.y - py
	var distance := SimMath.length(dx, dy)
	var reach := standing_body.push_radius + lying_body.lying_radius
	if distance >= reach:
		return
	## From the body toward the standing fighter; a centre exactly on the
	## body's axis is pushed off it across the axis, toward its own side.
	var nx := -uy
	var ny := ux
	if distance > SimMath.EPSILON:
		nx = dx / distance
		ny = dy / distance
	## Lever of the contact point about the body's centre of mass.
	var rx := px - body.x
	var ry := py - body.y
	var cross := rx * ny - ry * nx
	var standing_mass := standing_body.mass
	var lying_mass := lying_body.mass
	var moment := inertia(lying_body)
	## Velocity of the body's surface at the contact: its centre plus spin.
	var bvx := body.vx - body.fallen.spin * ry
	var bvy := body.vy + body.fallen.spin * rx
	var closing := (standing.vx - bvx) * nx + (standing.vy - bvy) * ny
	if closing < 0.0:
		var k := 1.0 / standing_mass + 1.0 / lying_mass + cross * cross / moment
		var impulse := -closing / k
		standing.vx += impulse * nx / standing_mass
		standing.vy += impulse * ny / standing_mass
		body.vx -= impulse * nx / lying_mass
		body.vy -= impulse * ny / lying_mass
		body.fallen.spin -= impulse * cross / moment
	## The overlap is cleared split by inverse mass, like every body contact.
	var overlap := reach + ArenaConstraints.BODY_CONTACT_REST_EPSILON - distance
	var standing_share := (1.0 / standing_mass) / (1.0 / standing_mass + 1.0 / lying_mass)
	var lying_share := 1.0 - standing_share
	standing.x += nx * overlap * standing_share
	standing.y += ny * overlap * standing_share
	body.x -= nx * overlap * lying_share
	body.y -= ny * overlap * lying_share
