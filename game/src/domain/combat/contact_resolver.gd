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
## The hard escape bound fired: neither fighter won, both are freed.
const REASON_ESCAPED := &"escaped"


## Resolve one contact. The caller has already rewound both fighters to the
## time of impact, so everything here reads live state; `toi` is carried only
## so consequences can be ordered within the tick.
static func resolve(
	state: MatchState,
	report: ContactReport,
	rules: DuelRules,
	tick: int,
	toi: float,
	events: Array[DuelEvent],
	scratches: Array[FighterTickScratch] = []
) -> void:
	if report.blade:
		_resolve_blades(state, report, rules, tick, events)
		return
	if report.body_push:
		_resolve_body_push(state, report, rules, tick, toi, events)
		return
	var strikes: Array[StrikeResult] = []
	for attacker in 2:
		if report.body[attacker]:
			## A blade in a bind is physically present but geometrically
			## constrained between the fighters — the consequence is suppressed
			## while the bind holds. Detection stays truthful; only the result
			## is gated (COMBAT-007).
			if state.fighter(attacker).weapon.phase == CombatPhase.Id.BIND:
				continue
			var strike := DamageModel.evaluate(
				state.fighter(attacker),
				state.opponent_of(attacker),
				report.body_x[attacker],
				report.body_y[attacker],
				rules,
			)
			strike.toi = toi
			strikes.append(strike)
	for strike in strikes:
		var target_scratch: FighterTickScratch = scratches[strike.target] if scratches.size() > strike.target else null
		_apply_strike(state, strike, rules, tick, events, target_scratch)


## Advance an active bind; release, disengage, or decide it.
##
## A bind may last, but it can never become unrecoverable (COMBAT §45). Three
## independent exits guarantee that: the blades separating, the authored bind
## duration running out, and a hard escape bound on how long the pair may sit
## in `BOUND` however it got there. Equal pressure decides nothing — a
## deadlock resolves as a mutual disengage rather than picking a slot.
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
		state.blade_contact.set_phase(ContactPairState.Phase.SEPARATING)
		events.append(DuelEvent.create(DuelEventTypes.BIND_ENDED, tick, held.slot, DuelEvent.NONE, {DuelEventKeys.REASON: String(REASON_RELEASED)}))
		return
	a.weapon.bind_left -= 1
	b.weapon.bind_left -= 1
	var separated := blade_gap(a, b, rules) > rules.weapon.blade_radius * 2.0 + rules.combat.bind_break_distance
	## However a bind was entered, the pair cannot sit in it forever.
	var stuck := state.blade_contact.phase_ticks >= rules.combat.bind_escape_ticks
	if not separated and a.weapon.bind_left > 0 and not stuck:
		return
	var winner := DuelEvent.NONE
	if not separated and not stuck:
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
	state.blade_contact.set_phase(ContactPairState.Phase.SEPARATING)
	var reason := REASON_DISENGAGED if separated else REASON_PRESSED
	if stuck and not separated:
		reason = REASON_ESCAPED
	events.append(DuelEvent.create(DuelEventTypes.BIND_ENDED, tick, winner, DuelEvent.NONE, {
		DuelEventKeys.REASON: String(reason),
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


## Inertia behind the blade: the weapon's own moment of inertia, scaled by how
## well the fighter's structure is supporting it. Better-coupled and more
## committed fighters push harder because more of them resists being
## displaced (PHYS-002).
##
## `strike_x` / `strike_y` is the unit direction the contact point is
## travelling, so the same motion that helps a cut also helps win a bind.
static func effective_inertia(fighter: FighterState, strike_x: float, strike_y: float, rules: DuelRules) -> float:
	var combat := rules.combat
	var coupling := StructuralCoupling.coupling(fighter, strike_x, strike_y, rules.fighter, combat)
	return (
		rules.weapon.moment_of_inertia()
		* SimMath.mix(combat.blade_inertia_coupling_floor, 1.0, coupling)
		* (1.0 + combat.blade_inertia_commit_bonus * fighter.weapon.commitment)
	)


## Resolve a body-body collision with an inverse-mass impulse (PHYS-005).
## A heavier fighter absorbs less velocity; restitution is low so bodies
## don't bounce. Tangential Coulomb friction sheds some sliding speed,
## bounded so a glancing bump cannot halt lateral motion entirely.
static func _resolve_body_push(
	state: MatchState,
	report: ContactReport,
	rules: DuelRules,
	tick: int,
	toi: float,
	events: Array[DuelEvent]
) -> void:
	var a := state.fighter(0)
	var b := state.fighter(1)
	var nx := report.body_push_nx
	var ny := report.body_push_ny
	var closing := (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
	if closing <= 0.0:
		return
	var mass_a := rules.fighter.mass
	var mass_b := rules.fighter.mass
	var inv_total := 1.0 / mass_a + 1.0 / mass_b
	if inv_total <= SimMath.EPSILON:
		return
	var impulse := (1.0 + rules.combat.body_restitution) * closing / inv_total
	a.vx -= (impulse / mass_a) * nx
	a.vy -= (impulse / mass_a) * ny
	b.vx += (impulse / mass_b) * nx
	b.vy += (impulse / mass_b) * ny
	## Tangential friction (PHYS-005). The tangent is perpendicular to the
	## contact normal; friction impulse is bounded by Coulomb's law so it
	## never exceeds what would zero out the sliding, and never exceeds
	## `body_friction × normal_impulse`.
	var tx := -ny
	var ty := nx
	var sliding := (a.vx - b.vx) * tx + (a.vy - b.vy) * ty
	var friction_impulse := 0.0
	if absf(sliding) > SimMath.EPSILON and rules.combat.body_friction > 0.0:
		var stop_impulse := absf(sliding) / inv_total
		friction_impulse = minf(rules.combat.body_friction * impulse, stop_impulse)
		var sign_s := signf(sliding)
		a.vx -= (friction_impulse / mass_a) * tx * sign_s
		a.vy -= (friction_impulse / mass_a) * ty * sign_s
		b.vx += (friction_impulse / mass_b) * tx * sign_s
		b.vy += (friction_impulse / mass_b) * ty * sign_s
	var px := (a.x + b.x) * 0.5
	var py := (a.y + b.y) * 0.5
	events.append(DuelEvent.create(DuelEventTypes.BODY_PUSH, tick, DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.X: px,
		DuelEventKeys.Y: py,
		DuelEventKeys.NORMAL_X: nx,
		DuelEventKeys.NORMAL_Y: ny,
		DuelEventKeys.CLOSING_SPEED: closing,
		DuelEventKeys.IMPULSE: impulse,
		DuelEventKeys.SLIDING_SPEED: absf(sliding),
		DuelEventKeys.TANGENTIAL_IMPULSE: friction_impulse,
		DuelEventKeys.TOI: toi,
	}))


static func _resolve_blades(
	state: MatchState,
	report: ContactReport,
	rules: DuelRules,
	tick: int,
	events: Array[DuelEvent]
) -> void:
	var weapon := rules.weapon
	var a := state.fighter(0)
	var b := state.fighter(1)
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
	var rax := px - a.x
	var ray := py - a.y
	var rbx := px - b.x
	var rby := py - b.y
	var normal_velocity := (a.vx - omega_a * ray - b.vx + omega_b * rby) * nx + (a.vy + omega_a * rax - b.vy - omega_b * rbx) * ny
	var closing := -normal_velocity
	if closing <= 0.0:
		return
	var cross_a := rax * ny - ray * nx
	var cross_b := rbx * ny - rby * nx
	var tangent_a := _contact_tangent(rax, ray, omega_a, a.weapon.swing_dir)
	var tangent_b := _contact_tangent(rbx, rby, omega_b, b.weapon.swing_dir)
	var inertia_a := effective_inertia(a, tangent_a[0], tangent_a[1], rules)
	var inertia_b := effective_inertia(b, tangent_b[0], tangent_b[1], rules)
	var denominator := cross_a * cross_a / inertia_a + cross_b * cross_b / inertia_b
	if denominator <= SimMath.EPSILON:
		return
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
		var keep_speed := weapon.deflect_fraction * weapon.achievable_swing_speed(
			fighter.weapon.swing_charge,
			fighter.weapon.launch_readiness
		)
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
		DuelEventKeys.INTENSITY: SwingSemantics.clash_intensity(closing, rules.combat),
		DuelEventKeys.CONTACT_CLASS: String(classify(closing, rules)),
		## The geometry of the clash, carried: the normal the blades met along
		## and the direction the striking point was travelling. Without these a
		## consumer has to rebuild the contact from fighter positions, which is
		## a guess that silently disagrees with the resolver.
		DuelEventKeys.NORMAL_X: nx,
		DuelEventKeys.NORMAL_Y: ny,
		DuelEventKeys.STRIKE_X: tangent_a[0] if attacker != 1 else tangent_b[0],
		DuelEventKeys.STRIKE_Y: tangent_a[1] if attacker != 1 else tangent_b[1],
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


## Unit direction a contact point at offset `(rx, ry)` is travelling under
## angular velocity `omega`. A blade momentarily at rest still has an intended
## direction, so `fallback_dir` keeps the result total.
static func _contact_tangent(rx: float, ry: float, omega: float, fallback_dir: float) -> PackedFloat64Array:
	var radius := SimMath.length(rx, ry)
	if radius <= SimMath.EPSILON:
		return PackedFloat64Array([0.0, 0.0])
	var turning := signf(omega) if absf(omega) > SimMath.EPSILON else fallback_dir
	return PackedFloat64Array([-ry / radius * turning, rx / radius * turning])


static func _start_bind(state: MatchState, rules: DuelRules, tick: int, events: Array[DuelEvent], px: float, py: float, closing: float) -> void:
	state.blade_contact.set_phase(ContactPairState.Phase.BOUND)
	for slot in 2:
		var fighter := state.fighter(slot)
		fighter.clear_attack_input()
		fighter.weapon.charge = 0.0
		fighter.weapon.earned_windback = 0.0
		fighter.weapon.speed = 0.0
		fighter.weapon.bind_left = rules.weapon.bind_ticks
		fighter.weapon.set_phase(CombatPhase.Id.BIND)
	events.append(DuelEvent.create(DuelEventTypes.BIND_STARTED, tick, DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.X: px,
		DuelEventKeys.Y: py,
		DuelEventKeys.CLOSING_SPEED: closing,
		DuelEventKeys.INTENSITY: SwingSemantics.clash_intensity(closing, rules.combat),
	}))


## Apply one strike. Every consequence is driven by the physical quantity that
## actually causes it (PHYS-004): severity injures, impulse displaces and
## unbalances, and exposure modifies only how badly the target copes.
##
## PHYS-008: Conditional weapon/body coupling. For non-stabbing contacts, the
## target receives pushback AND the blade receives an opposite reactive angular
## impulse from the contact lever arm and weapon inertia. For stabbing-angle
## contacts (point-first entry), the target receives pushback but the blade
## receives no reactive impulse — it penetrates cleanly.
static func _apply_strike(state: MatchState, strike: StrikeResult, rules: DuelRules, tick: int, events: Array[DuelEvent], target_scratch: FighterTickScratch = null) -> void:
	var impact := strike.impact
	var attacker := state.fighter(strike.attacker)
	var target := state.fighter(strike.target)
	target.health = maxf(0.0, target.health - strike.damage)
	var shock := StaminaModel.damage_shock(strike.damage, rules.combat)
	if target_scratch != null:
		target_scratch.contact_shock += shock
	## Target pushback: physical impulse × game-feel scale (PHYS-008). The
	## extra feel scale is never reflected back into blade reaction.
	var push := impact.target_delta_v() * rules.combat.body_push_feel_scale
	target.vx += impact.normal_x * push
	target.vy += impact.normal_y * push
	## Blade reaction (PHYS-008): for non-stabbing contacts, compute an
	## opposite reactive angular impulse on the weapon using the weapon's
	## effective mass at the contact point (I/r²) and the target's effective
	## mass. A well-braced fighter keeps the blade driving through; only the
	## weapon's mass-share of the collision decelerates the swing.
	if not strike.is_stabbing:
		var rx := impact.point_x - attacker.x
		var ry := impact.point_y - attacker.y
		var r_sq := rx * rx + ry * ry
		if r_sq > SimMath.EPSILON:
			var weapon_moi := rules.weapon.moment_of_inertia()
			var weapon_eff := weapon_moi / r_sq
			var target_eff := impact.target_effective_mass
			if target_eff > SimMath.EPSILON:
				var reduced := weapon_eff * target_eff / (weapon_eff + target_eff)
				var lever_cross := ry * impact.normal_x - rx * impact.normal_y
				var j_reaction := reduced * impact.normal_speed
				attacker.weapon.speed += j_reaction * lever_cross / weapon_moi
	var payload := strike.to_payload()
	payload[DuelEventKeys.PUSH] = push
	payload[DuelEventKeys.HEALTH] = target.health
	payload[DuelEventKeys.STAMINA] = shock
	payload[DuelEventKeys.THRUST_ALIGNMENT] = strike.impact.thrust_alignment
	payload[DuelEventKeys.INCIDENCE_QUALITY] = strike.impact.incidence_quality
	events.append(DuelEvent.create(DuelEventTypes.BODY_HIT, tick, attacker.slot, target.slot, payload))
	if strike.contact_kind == StrikeResult.ContactKind.POKE:
		events.append(DuelEvent.create(DuelEventTypes.BODY_POKE, tick, attacker.slot, target.slot, strike.to_payload()))
	elif strike.contact_kind == StrikeResult.ContactKind.THRUST:
		events.append(DuelEvent.create(DuelEventTypes.BODY_THRUST, tick, attacker.slot, target.slot, strike.to_payload()))
	if strike.critical:
		events.append(DuelEvent.create(DuelEventTypes.CRITICAL_HIT, tick, attacker.slot, target.slot, strike.to_payload()))
	if not target.is_alive():
		WeaponSystem.kill(target, strike.toi)
		events.append(DuelEvent.create(DuelEventTypes.FIGHTER_KILLED, tick, attacker.slot, target.slot, {DuelEventKeys.X: target.x, DuelEventKeys.Y: target.y}))
	elif strike.stagger_pressure >= rules.weapon.stagger_impulse:
		var ticks := rules.weapon.stagger_base_ticks + roundi(rules.weapon.stagger_scale_ticks * strike.stagger_pressure)
		WeaponSystem.stagger(target, ticks)
		events.append(DuelEvent.create(DuelEventTypes.STAGGERED, tick, target.slot, attacker.slot, {DuelEventKeys.TICKS: ticks}))
