class_name ContactResolver
extends RefCounted

## Turns contact into persistent combat consequences (COMBAT §40–§45, §55–§59).
##
## Blade contact is a 2D rigid impulse about each fighter's pivot: the faster,
## heavier, better-planted blade displaces the other. A swing slowed below the
## deflect fraction is interrupted into recovery. Low-energy contact binds.
## A parry is classified, never input: the defender ends up threatening first.
## Body hits are evaluated against pre-hit state, then applied together, so a
## true double hit stays symmetric.
##
## Implements: /spec/invariants.md#combat-003
## See also: /docs/concepts/combat.md

const CLASS_LIGHT := &"light"
const CLASS_SOLID := &"solid"
const CLASS_STRONG := &"strong"
const REASON_DISENGAGED := &"disengaged"
const REASON_PRESSED := &"pressed"
const REASON_RELEASED := &"released"


static func resolve(
	state: MatchState,
	report: ContactReport,
	start: Array[FighterPose],
	rules: DuelRules,
	tick: int,
	events: Array[DuelEvent]
) -> void:
	if report.blade:
		_resolve_blades(state, report, start, rules, tick, events)
		return
	var strikes: Array[StrikeResult] = []
	for attacker in 2:
		if report.body[attacker]:
			strikes.append(DamageModel.evaluate(
				state.fighter(attacker),
				state.opponent_of(attacker),
				report.body_x[attacker],
				report.body_y[attacker],
				rules
			))
	for strike in strikes:
		_apply_strike(state, strike, rules, tick, events)


## Advance an active bind; release, disengage, or decide it.
static func update_bind(state: MatchState, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var a := state.fighter(0)
	var b := state.fighter(1)
	var a_bound := a.weapon.phase == CombatPhase.Id.BIND
	var b_bound := b.weapon.phase == CombatPhase.Id.BIND
	if not a_bound and not b_bound:
		return
	if a_bound != b_bound:
		var held := a if a_bound else b
		held.weapon.bind_left = 0
		held.weapon.set_phase(CombatPhase.Id.NEUTRAL)
		events.append(DuelEvent.create(DuelEventTypes.BIND_ENDED, tick, held.slot, DuelEvent.NONE, {DuelEventKeys.REASON: String(REASON_RELEASED)}))
		return
	a.weapon.bind_left -= 1
	b.weapon.bind_left -= 1
	var separated := blade_gap(a, b, rules) > rules.weapon.blade_radius * 2.0 + rules.combat.bind_break_distance
	if not separated and a.weapon.bind_left > 0:
		return
	var winner := DuelEvent.NONE
	if not separated:
		var pressure_a := bind_pressure(a, b)
		var pressure_b := bind_pressure(b, a)
		if pressure_a > pressure_b + SimMath.EPSILON:
			winner = 0
		elif pressure_b > pressure_a + SimMath.EPSILON:
			winner = 1
	for slot in 2:
		var fighter := state.fighter(slot)
		fighter.weapon.bind_left = 0
		if winner != DuelEvent.NONE and slot != winner:
			fighter.weapon.recovery_commitment = 0.0
			WeaponSystem.enter_recovery(fighter.weapon, rules.weapon.bind_loser_recovery_ticks)
		else:
			fighter.weapon.set_phase(CombatPhase.Id.NEUTRAL)
	events.append(DuelEvent.create(DuelEventTypes.BIND_ENDED, tick, winner, DuelEvent.NONE, {
		DuelEventKeys.REASON: String(REASON_DISENGAGED if separated else REASON_PRESSED),
	}))


## A planted fighter square to the opponent wins the bind.
static func bind_pressure(fighter: FighterState, opponent: FighterState) -> float:
	return fighter.stability * (1.0 - absf(DuelGeometry.facing_error(fighter, opponent)) / PI)


## Current closest distance between the two blade segments.
static func blade_gap(a: FighterState, b: FighterState, rules: DuelRules) -> float:
	var weapon := rules.weapon
	var angle_a := DuelGeometry.blade_angle(a)
	var angle_b := DuelGeometry.blade_angle(b)
	var ax := SimMath.cosine(angle_a)
	var ay := SimMath.sine(angle_a)
	var bx := SimMath.cosine(angle_b)
	var by := SimMath.sine(angle_b)
	var contact := SegmentContact.new()
	SimMath.closest_segments(
		a.x + ax * weapon.hilt_radius, a.y + ay * weapon.hilt_radius,
		a.x + ax * weapon.tip_radius, a.y + ay * weapon.tip_radius,
		b.x + bx * weapon.hilt_radius, b.y + by * weapon.hilt_radius,
		b.x + bx * weapon.tip_radius, b.y + by * weapon.tip_radius,
		contact
	)
	return contact.distance


static func classify(closing_speed: float, rules: DuelRules) -> StringName:
	if closing_speed >= rules.combat.blade_strong_speed:
		return CLASS_STRONG
	if closing_speed >= rules.combat.blade_solid_speed:
		return CLASS_SOLID
	return CLASS_LIGHT


## Inertia behind the blade: planted and committed fighters push harder.
static func effective_inertia(fighter: FighterState, rules: DuelRules) -> float:
	var combat := rules.combat
	return (
		rules.weapon.inertia
		* SimMath.mix(combat.blade_inertia_stability_floor, 1.0, fighter.stability)
		* (1.0 + combat.blade_inertia_commit_bonus * fighter.weapon.commitment)
	)


static func _resolve_blades(
	state: MatchState,
	report: ContactReport,
	start: Array[FighterPose],
	rules: DuelRules,
	tick: int,
	events: Array[DuelEvent]
) -> void:
	var weapon := rules.weapon
	var a := state.fighter(0)
	var b := state.fighter(1)
	for slot in 2:
		var fighter := state.fighter(slot)
		fighter.weapon.angle = SimMath.mix(start[slot].weapon_angle, fighter.weapon.angle, report.fraction)
	var px := (report.blade_ax + report.blade_bx) * 0.5
	var py := (report.blade_ay + report.blade_by) * 0.5
	var nx := report.blade_ax - report.blade_bx
	var ny := report.blade_ay - report.blade_by
	var gap := SimMath.length(nx, ny)
	if gap > SimMath.EPSILON:
		nx /= gap
		ny /= gap
	else:
		var angle_b := DuelGeometry.blade_angle(b)
		nx = -SimMath.sine(angle_b)
		ny = SimMath.cosine(angle_b)
		if nx * (a.x - px) + ny * (a.y - py) < 0.0:
			nx = -nx
			ny = -ny
	var omega_a := a.turn_rate + a.weapon.speed
	var omega_b := b.turn_rate + b.weapon.speed
	var rax := px - SimMath.mix(start[0].x, a.x, report.fraction)
	var ray := py - SimMath.mix(start[0].y, a.y, report.fraction)
	var rbx := px - SimMath.mix(start[1].x, b.x, report.fraction)
	var rby := py - SimMath.mix(start[1].y, b.y, report.fraction)
	var normal_velocity := (a.vx - omega_a * ray - b.vx + omega_b * rby) * nx + (a.vy + omega_a * rax - b.vy - omega_b * rbx) * ny
	var closing := -normal_velocity
	if closing <= 0.0:
		return
	var cross_a := rax * ny - ray * nx
	var cross_b := rbx * ny - rby * nx
	var inertia_a := effective_inertia(a, rules)
	var inertia_b := effective_inertia(b, rules)
	var denominator := cross_a * cross_a / inertia_a + cross_b * cross_b / inertia_b
	if denominator <= SimMath.EPSILON:
		return
	state.blade_cooldown = weapon.contact_cooldown_ticks
	a.weapon.swing_contact = true
	b.weapon.swing_contact = true
	if closing < weapon.bind_speed:
		_start_bind(state, rules, tick, events, px, py, closing)
		return
	var swinging: Array[bool] = [CombatPhase.is_swinging(a.weapon.phase), CombatPhase.is_swinging(b.weapon.phase)]
	var impulse := (1.0 + weapon.restitution) * closing / denominator
	var deltas := PackedFloat64Array([impulse * cross_a / inertia_a, -impulse * cross_b / inertia_b])
	a.weapon.speed += deltas[0]
	b.weapon.speed += deltas[1]
	var deflected: Array[bool] = [false, false]
	for slot in 2:
		var fighter := state.fighter(slot)
		var keep_speed := weapon.deflect_fraction * weapon.swing_speed(fighter.weapon.swing_charge)
		if swinging[slot] and fighter.weapon.speed * fighter.weapon.swing_dir < keep_speed:
			WeaponSystem.begin_recovery(fighter, state.opponent_of(slot), rules, absf(deltas[slot]))
			deflected[slot] = true
	var attacker := DuelEvent.NONE
	if swinging[0] != swinging[1]:
		attacker = 0 if swinging[0] else 1
	events.append(DuelEvent.create(DuelEventTypes.BLADE_CONTACT, tick, attacker, DuelEvent.NONE if attacker == DuelEvent.NONE else 1 - attacker, {
		DuelEventKeys.X: px,
		DuelEventKeys.Y: py,
		DuelEventKeys.CLOSING_SPEED: closing,
		DuelEventKeys.IMPULSE: impulse,
		DuelEventKeys.CONTACT_CLASS: String(classify(closing, rules)),
		DuelEventKeys.DEFLECTED_0: deflected[0],
		DuelEventKeys.DEFLECTED_1: deflected[1],
		DuelEventKeys.DELTA_0: deltas[0],
		DuelEventKeys.DELTA_1: deltas[1],
	}))
	if attacker == DuelEvent.NONE:
		return
	var striker := state.fighter(attacker)
	var defender := state.opponent_of(attacker)
	var margin := InitiativeModel.time_to_threat(striker, defender, rules) - InitiativeModel.time_to_threat(defender, striker, rules)
	if margin >= rules.combat.parry_margin_seconds:
		events.append(DuelEvent.create(DuelEventTypes.PARRY, tick, defender.slot, striker.slot, {DuelEventKeys.MARGIN: margin, DuelEventKeys.X: px, DuelEventKeys.Y: py}))


static func _start_bind(state: MatchState, rules: DuelRules, tick: int, events: Array[DuelEvent], px: float, py: float, closing: float) -> void:
	for slot in 2:
		var fighter := state.fighter(slot)
		fighter.clear_attack_input()
		fighter.weapon.charge = 0.0
		fighter.weapon.speed = 0.0
		fighter.weapon.bind_left = rules.weapon.bind_ticks
		fighter.weapon.set_phase(CombatPhase.Id.BIND)
	events.append(DuelEvent.create(DuelEventTypes.BIND_STARTED, tick, DuelEvent.NONE, DuelEvent.NONE, {DuelEventKeys.X: px, DuelEventKeys.Y: py, DuelEventKeys.CLOSING_SPEED: closing}))


static func _apply_strike(state: MatchState, strike: StrikeResult, rules: DuelRules, tick: int, events: Array[DuelEvent]) -> void:
	var weapon := rules.weapon
	var attacker := state.fighter(strike.attacker)
	var target := state.fighter(strike.target)
	attacker.weapon.swing_hit = true
	attacker.weapon.swing_contact = true
	target.health = maxf(0.0, target.health - strike.damage)
	var push := weapon.knockback_speed * minf(strike.quality, 1.0)
	target.vx += strike.normal_x * push
	target.vy += strike.normal_y * push
	var payload := strike.to_payload()
	payload[DuelEventKeys.HEALTH] = target.health
	events.append(DuelEvent.create(DuelEventTypes.BODY_HIT, tick, attacker.slot, target.slot, payload))
	if strike.critical:
		events.append(DuelEvent.create(DuelEventTypes.CRITICAL_HIT, tick, attacker.slot, target.slot, strike.to_payload()))
	if not target.is_alive():
		WeaponSystem.kill(target)
		events.append(DuelEvent.create(DuelEventTypes.FIGHTER_KILLED, tick, attacker.slot, target.slot, {DuelEventKeys.X: target.x, DuelEventKeys.Y: target.y}))
	elif strike.quality >= weapon.stagger_quality:
		var ticks := weapon.stagger_base_ticks + roundi(weapon.stagger_scale_ticks * strike.quality)
		WeaponSystem.stagger(target, ticks)
		events.append(DuelEvent.create(DuelEventTypes.STAGGERED, tick, target.slot, attacker.slot, {DuelEventKeys.TICKS: ticks}))
	var stop := weapon.swing_stop_base + weapon.swing_stop_scale * minf(strike.quality, 1.0)
	attacker.weapon.speed *= 1.0 - stop
	if strike.quality >= weapon.swing_end_quality and CombatPhase.is_swinging(attacker.weapon.phase):
		attacker.weapon.set_phase(CombatPhase.Id.OVERSWING)
