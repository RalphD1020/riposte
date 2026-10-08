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
	var has_constraining := report.sword_body_constraining[0] or report.sword_body_constraining[1]
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
	if has_constraining:
		for attacker in 2:
			if report.sword_body_constraining[attacker]:
				_enforce_sword_body_nonpenetration(state, attacker, rules)


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


## Resolve a body-body contact (PHYS-005, PHYS-009). First contact applies
## restitution-based impulse. Persistent contact applies a zero-restitution
## nonpenetration constraint — the motors have already produced velocity, and
## the constraint only cancels inward relative normal velocity. This prevents
## double-counting motor force.
##
## Contact normal is derived from live geometry (current positions), not frozen.
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
	## Derive contact normal from current body positions (live geometry).
	var dx := b.x - a.x
	var dy := b.y - a.y
	var dist := SimMath.length(dx, dy)
	var nx := dx / dist if dist > SimMath.EPSILON else report.body_push_nx
	var ny := dy / dist if dist > SimMath.EPSILON else report.body_push_ny
	## Store fallback normal for numerically coincident centers.
	state.body_contact.prev_normal_x = nx
	state.body_contact.prev_normal_y = ny
	var closing := (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
	if closing <= 0.0:
		return
	var mass_a := rules.fighter.mass
	var mass_b := rules.fighter.mass
	var inv_total := 1.0 / mass_a + 1.0 / mass_b
	if inv_total <= SimMath.EPSILON:
		return
	## New contact: authored restitution. Persistent: zero restitution (constraint only).
	var restitution := rules.combat.body_restitution if not report.body_push_persistent else 0.0
	var impulse := (1.0 + restitution) * closing / inv_total
	## Expose the solved impulse for CPU observation (CPU-007).
	state.body_contact.last_constraint_impulse = impulse
	state.body_contact.last_constraint_normal_x = nx
	state.body_contact.last_constraint_normal_y = ny
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
	## Burst termination on body impact (MOVE-002). A forward dash that
	## collides with a body terminates the burst motor. The impact impulse
	## was computed from actual closing velocity (including burst speed),
	## creating a heavy shove. The fighter enters recovery.
	if not report.body_push_persistent:
		for slot in 2:
			var fighter := state.fighter(slot)
			if fighter.gesture.is_bursting() and fighter.gesture.burst_kind == MovementGestureState.BurstKind.FORWARD_DASH:
				fighter.gesture.end_burst_into_recovery(rules.fighter.dash_recovery_ticks)


## Persistent sword-body nonpenetration (PHYS-010). Zero-restitution velocity
## constraint on the blade-to-body normal: if the blade is closing on the body
## center, apply the minimum impulse to bring relative normal velocity to zero.
## Same philosophy as persistent body-body contact — motors have already
## produced velocity; the constraint only prevents interpenetration.
static func _enforce_sword_body_nonpenetration(state: MatchState, attacker_slot: int, rules: DuelRules) -> void:
	var attacker := state.fighter(attacker_slot)
	var target := state.opponent_of(attacker_slot)
	var weapon := rules.weapon
	## Blade contact point: closest point on the blade segment to the target center.
	var blade_angle := DuelGeometry.blade_angle(attacker)
	var ux := SimMath.cosine(blade_angle)
	var uy := SimMath.sine(blade_angle)
	var hx := attacker.x + ux * weapon.hilt_radius
	var hy := attacker.y + uy * weapon.hilt_radius
	var tx := attacker.x + ux * weapon.tip_radius
	var ty := attacker.y + uy * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, target.x, target.y)
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	## Contact normal: from contact point toward the target center.
	var dx := target.x - px
	var dy := target.y - py
	var dist := SimMath.length(dx, dy)
	if dist < SimMath.EPSILON:
		return
	var nx := dx / dist
	var ny := dy / dist
	## Relative velocity at the contact point: blade velocity minus target velocity.
	var rx := px - attacker.x
	var ry := py - attacker.y
	var omega := attacker.turn_rate + attacker.weapon.speed
	var rel_vx := attacker.vx - omega * ry - target.vx
	var rel_vy := attacker.vy + omega * rx - target.vy
	var closing := rel_vx * nx + rel_vy * ny
	if closing <= 0.0:
		return
	## Inverse effective mass k = 1/m_T + 1/m_A + (r×n)²/I_A.
	var weapon_moi := weapon.moment_of_inertia()
	var mass_a := rules.fighter.mass
	var mass_t := StructuralCoupling.resisting_mass(target, rules.fighter, rules.combat)
	var lever_cross := rx * ny - ry * nx
	var inv_k := 0.0
	if mass_t > SimMath.EPSILON:
		inv_k += 1.0 / mass_t
	if mass_a > SimMath.EPSILON:
		inv_k += 1.0 / mass_a
	if weapon_moi > SimMath.EPSILON:
		inv_k += lever_cross * lever_cross / weapon_moi
	if inv_k < SimMath.EPSILON:
		return
	## Zero-restitution constraint: J = closing / k.
	var j := closing / inv_k
	if mass_t > SimMath.EPSILON:
		var dv_t := j / mass_t
		target.vx += nx * dv_t
		target.vy += ny * dv_t
	if mass_a > SimMath.EPSILON:
		var dv_a := j / mass_a
		attacker.vx -= nx * dv_a
		attacker.vy -= ny * dv_a
	if weapon_moi > SimMath.EPSILON:
		attacker.weapon.speed -= j * lever_cross / weapon_moi


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
## PHYS-010: Bilateral sword-body impulse. One authoritative J computed from
## proper inverse effective mass k = 1/m_T + 1/m_A + (r×n)²/I_A. Target
## linear, attacker linear, and sword angular reactions are all derived from
## that single J. For stabbing contacts the angular term is excluded and no
## blade reaction is applied; the impulse still transfers bilaterally between
## bodies. Lethal contacts apply a reduced fraction of the blocking impulse
## before releasing the nonpenetration constraint.
static func _apply_strike(state: MatchState, strike: StrikeResult, rules: DuelRules, tick: int, events: Array[DuelEvent], target_scratch: FighterTickScratch = null) -> void:
	var impact := strike.impact
	var attacker := state.fighter(strike.attacker)
	var target := state.fighter(strike.target)
	target.health = maxf(0.0, target.health - strike.damage)
	var shock := StaminaModel.damage_shock(strike.damage, rules.combat)
	if target_scratch != null:
		target_scratch.contact_shock += shock
	## Bilateral impulse (PHYS-010). Recompute k for the actual classification:
	## stabbing excludes the angular term because the blade penetrates cleanly.
	var weapon_moi := rules.weapon.moment_of_inertia()
	var inv_k := 0.0
	if impact.target_effective_mass > SimMath.EPSILON:
		inv_k += 1.0 / impact.target_effective_mass
	if impact.attacker_effective_mass > SimMath.EPSILON:
		inv_k += 1.0 / impact.attacker_effective_mass
	if not strike.is_stabbing and weapon_moi > SimMath.EPSILON:
		inv_k += impact.lever_cross * impact.lever_cross / weapon_moi
	var restitution := rules.combat.sword_body_restitution
	var bilateral_j := 0.0
	if inv_k > SimMath.EPSILON:
		bilateral_j = (1.0 + restitution) * impact.normal_speed / inv_k
	## Lethal contacts apply only a fraction of the full blocking impulse.
	if strike.lethal:
		bilateral_j *= rules.combat.penetration_resistance_fraction
	## Target linear reaction: pushed away from the blade.
	if impact.target_effective_mass > SimMath.EPSILON:
		var dv_target := bilateral_j / impact.target_effective_mass
		target.vx += impact.normal_x * dv_target
		target.vy += impact.normal_y * dv_target
	## Attacker linear reaction: pushed back by Newton's third law.
	if impact.attacker_effective_mass > SimMath.EPSILON:
		var dv_attacker := bilateral_j / impact.attacker_effective_mass
		attacker.vx -= impact.normal_x * dv_attacker
		attacker.vy -= impact.normal_y * dv_attacker
	## Sword angular reaction (non-stab only): derived from the same J.
	if not strike.is_stabbing and weapon_moi > SimMath.EPSILON:
		attacker.weapon.speed -= bilateral_j * impact.lever_cross / weapon_moi
	## Advance weapon-body lifecycle: nonlethal → CONSTRAINING, lethal → PENETRATING.
	state.weapon_body_contacts[strike.attacker].advance_after_entry(strike.lethal)
	var push := 0.0
	if impact.target_effective_mass > SimMath.EPSILON:
		push = bilateral_j / impact.target_effective_mass
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
