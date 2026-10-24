class_name ContactResolver
extends RefCounted

## Turns contact into persistent combat consequences (COMBAT §40–§45, §55–§59).
##
## Blade contact is an impulse in weapon coordinates, solved by
## `SwordContactSolver` and recorded on the `SwordContactSet`: the faster,
## heavier, better-planted blade displaces the other. A slow first contact is
## inelastic (below `restitution_threshold_speed`) and simply persists; the
## rigid solver then keeps the blades apart while they slide freely. There is
## no scripted bind: a bind is what persistent contact looks like, never a
## state that zeroes speeds or picks a winner (RIGID-CONTACT-002). A swing is
## interrupted only when a contact actually arrested it (`arrests`).
## A parry is classified, never input: the defender's sword physically
## intercepted and arrested the cut (PARRY-001).
## Body hits are evaluated against pre-hit state, then applied together, so a
## true double hit stays symmetric.
##
## Implements: /spec/invariants.md#combat-003
## Implements: /spec/invariants.md#rigid-contact-002
## See also: /docs/concepts/combat.md

const CLASS_LIGHT := &"light"
const CLASS_SOLID := &"solid"
const CLASS_STRONG := &"strong"
## Two points' normal impulses closer than this share of the total are an even
## split: the event is named by point 0 (rounding never picks a side).
const EVEN_SPLIT := 1.0e-9


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
	scratches: Array[FighterTickScratch] = [],
	lcp: ContactLcp = null
) -> void:
	if report.blade:
		_resolve_blades(state, rules, tick, events, lcp if lcp != null else ContactLcp.new(), scratches)
		return
	if report.structure[0] or report.structure[1]:
		for slot in 2:
			if report.structure[slot]:
				_resolve_structure(state, rules, slot, tick, toi, events, lcp if lcp != null else ContactLcp.new(), scratches)
		return
	if report.structure[0] or report.structure[1]:
		## The two swords share no coordinate with each other here, so the
		## order of the two solves changes nothing.
		for slot in 2:
			if report.structure[slot]:
				_resolve_structure(state, rules, slot, tick, toi, events, lcp if lcp != null else ContactLcp.new(), scratches)
		return
	if report.body_push:
		_resolve_body_push(state, report, rules, tick, toi, events)
		return
	var strikes: Array[StrikeResult] = []
	for attacker in 2:
		if report.body[attacker]:
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
		_apply_strike(state, strike, rules, tick, events, scratches)


## Closing-speed band for the clang (`light` / `solid` / `strong`). Not the
## tactical reading: a cut that keeps its progress is a glance
## (`ContactReading`) even when this band is `solid`.
static func classify(closing_speed: float, rules: DuelRules) -> StringName:
	if closing_speed >= rules.combat.blade_strong_speed:
		return CLASS_STRONG
	if closing_speed >= rules.combat.blade_solid_speed:
		return CLASS_SOLID
	return CLASS_LIGHT


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
	var mass_a := rules.combatant(0).fighter.mass
	var mass_b := rules.combatant(1).fighter.mass
	var inv_total := 1.0 / mass_a + 1.0 / mass_b
	if inv_total <= SimMath.EPSILON:
		return
	## New contact: the bodies' pair restitution. Persistent: zero (constraint only).
	var flesh := rules.body_pair()
	var restitution := flesh.restitution_at(closing) if not report.body_push_persistent else 0.0
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
	## `μ × normal_impulse` for the bodies' pair.
	var tx := -ny
	var ty := nx
	var sliding := (a.vx - b.vx) * tx + (a.vy - b.vy) * ty
	var friction_impulse := 0.0
	if absf(sliding) > SimMath.EPSILON and flesh.friction > 0.0:
		var stop_impulse := absf(sliding) / inv_total
		friction_impulse = minf(flesh.friction * impulse, stop_impulse)
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
				fighter.gesture.end_burst_into_recovery(rules.spec_of(fighter).fighter.dash_recovery_ticks)


## A first sword contact, solved on the points the sweep recorded at its time
## of impact (the manifold), never on a re-measured or reported midpoint.
static func _resolve_blades(
	state: MatchState,
	rules: DuelRules,
	tick: int,
	events: Array[DuelEvent],
	lcp: ContactLcp,
	scratches: Array[FighterTickScratch] = []
) -> void:
	var a := state.fighter(0)
	var b := state.fighter(1)
	var spec_a := rules.combatant(0)
	var spec_b := rules.combatant(1)
	var manifold := state.blade_contact
	var points := manifold.point_count
	if points == 0:
		return
	var pose_a := WeaponKinematics.pose_of(a, spec_a, BladePose.new())
	var pose_b := WeaponKinematics.pose_of(b, spec_b, BladePose.new())
	## The solve uses every touching point; the event is placed at their
	## centroid (a line contact's middle) and named by the point that took the
	## most impulse.
	var px := 0.0
	var py := 0.0
	for i in points:
		px += manifold.point_x[i]
		py += manifold.point_y[i]
	px /= float(points)
	py /= float(points)
	var closing_rows := PackedFloat64Array()
	closing_rows.resize(points)
	var separation_rows := PackedFloat64Array()
	separation_rows.resize(points)
	var closing := -INF
	for i in points:
		closing_rows[i] = SwordContactSolver.closing_speed(a, b, pose_a, pose_b, manifold.point_x[i], manifold.point_y[i], manifold.point_nx[i], manifold.point_ny[i])
		closing = maxf(closing, closing_rows[i])
	if closing <= 0.0:
		return
	## Each side is a held sword (ContactMechanics): its weapon coordinate (the
	## sword and the hands riding its grip) and the wielder's whole body
	## behind it. Near the hands, where the levers vanish, the bodies carry
	## the contact. One mass per coordinate for the whole solve, a property of
	## each held sword's pose and body — the same whichever point is read.
	var held := PackedFloat64Array([0.0, 0.0])
	ContactMechanics.held_sword(a, pose_a, manifold.point_x[0], manifold.point_y[0], spec_a, held)
	var inertia_a := held[0]
	var inverse_mass_a := held[1]
	ContactMechanics.held_sword(b, pose_b, manifold.point_x[0], manifold.point_y[0], spec_b, held)
	var inertia_b := held[0]
	var inverse_mass_b := held[1]
	var swinging: Array[bool] = [CombatPhase.is_swinging(a.weapon.phase), CombatPhase.is_swinging(b.weapon.phase)]
	var outcome := ContactOutcome.new()
	outcome.point_count = points
	outcome.closing_before = closing
	if swinging[0] != swinging[1]:
		outcome.attacker = 0 if swinging[0] else 1
	var root_vx := PackedFloat64Array([a.vx, b.vx])
	var root_vy := PackedFloat64Array([a.vy, b.vy])
	## Only an attack's first opponent contact can mark a deflection, so only it
	## pays for the line reading.
	var first_contact := false
	if outcome.attacker != DuelEvent.NONE:
		var cutting := state.fighter(outcome.attacker)
		outcome.attack_progress_before = cutting.weapon.speed * cutting.weapon.swing_dir
		first_contact = not cutting.weapon.attack_contacted
		if first_contact:
			outcome.threatened_before = _cut_threatens(state, rules, outcome.attacker)
	var deltas := PackedFloat64Array([0.0, 0.0])
	var impulse := 0.0
	var primary := 0
	## One energy law (IMPACT-PHYSICS-001): what the whole solve took out of
	## the coordinates it moved, in the masses it moved them with.
	var energy_before := SwordContactSolver.kinetic_energy(a, b, inertia_a, inertia_b, inverse_mass_a, inverse_mass_b)
	if points == 1:
		var nx1 := manifold.point_nx[0]
		var ny1 := manifold.point_ny[0]
		var cross_a := WeaponKinematics.lever(a, pose_a, px, py, nx1, ny1)
		var cross_b := WeaponKinematics.lever(b, pose_b, px, py, nx1, ny1)
		var denominator := cross_a * cross_a / inertia_a + cross_b * cross_b / inertia_b + inverse_mass_a + inverse_mass_b
		if denominator <= SimMath.EPSILON:
			return
		manifold.set_normal(nx1, ny1)
		var steel := rules.blade_pair()
		impulse = SwordContactSolver.solve(
			manifold, 0, a, b, pose_a, pose_b, px, py, closing, cross_a, cross_b, inertia_a, inertia_b,
			steel.restitution_at(closing), steel.friction, deltas, inverse_mass_a, inverse_mass_b
		)
	else:
		impulse = SwordContactSolver.solve_points(manifold, a, b, pose_a, pose_b, rules.blade_pair(), inertia_a, inertia_b, inverse_mass_a, inverse_mass_b, deltas, closing_rows, separation_rows, lcp)
		## Named by the point that took clearly the most of the impulse; an
		## even split (a line contact) by the earlier point, so a scene and its
		## mirror agree.
		for i in range(1, points):
			if manifold.normal_impulse[i] - manifold.normal_impulse[primary] > EVEN_SPLIT * impulse:
				primary = i
		manifold.set_normal(manifold.point_nx[primary], manifold.point_ny[primary])
	## A solved clash is opponent contact for both attacks; a speculative
	## touch that took no impulse is not.
	if impulse > 0.0:
		a.weapon.attack_contacted = true
		b.weapon.attack_contacted = true
		## The first impact is the steel episode. `deltas` is each sword's own
		## contact-caused change in angular velocity; the shared normal impulse
		## is not. A later hold of this episode is the rigid solve, not another
		## dip (IMPACT-AUTHORITY-001).
		var floor_value := rules.combat.impact_authority_floor
		for slot in 2:
			var fighter := state.fighter(slot)
			var full_swing := (spec_a if slot == 0 else spec_b).weapon.swing_speed_full
			var next := ImpactAuthority.after_episode(fighter.impact_authority, deltas[slot], full_swing, floor_value)
			if next < fighter.impact_authority and slot < scratches.size():
				scratches[slot].authority_dipped = true
			fighter.impact_authority = next
	var energy := maxf(energy_before - SwordContactSolver.kinetic_energy(a, b, inertia_a, inertia_b, inverse_mass_a, inverse_mass_b), 0.0)
	var nx := manifold.normal_x
	var ny := manifold.normal_y
	## Where on each blade the event says the contact was: a line contact
	## (both its points) at its middle, like its location.
	var fraction_a := 0.0
	var fraction_b := 0.0
	for i in points:
		fraction_a += manifold.fraction_a[i]
		fraction_b += manifold.fraction_b[i]
	fraction_a /= float(points)
	fraction_b /= float(points)
	var tangent_a := ContactMechanics.contact_tangent(px - a.x, py - a.y, a.turn_rate + a.weapon.speed, a.weapon.swing_dir)
	var tangent_b := ContactMechanics.contact_tangent(px - b.x, py - b.y, b.turn_rate + b.weapon.speed, b.weapon.swing_dir)
	_read_outcome(outcome, manifold, a, b, pose_a, pose_b, root_vx, root_vy, deltas, rules)
	for slot in 2:
		if swinging[slot]:
			outcome.arrested[slot] = _interrupt_if_arrested(state, slot, rules, deltas[slot], scratches)
	var attacker := outcome.attacker
	if attacker != DuelEvent.NONE:
		var cut := state.fighter(attacker)
		outcome.attack_progress_after = cut.weapon.speed * cut.weapon.swing_dir
	events.append(DuelEvent.create(DuelEventTypes.BLADE_CONTACT, tick, attacker, DuelEvent.NONE if attacker == DuelEvent.NONE else 1 - attacker, {
		DuelEventKeys.X: px,
		DuelEventKeys.Y: py,
		DuelEventKeys.CLOSING_SPEED: closing,
		DuelEventKeys.IMPULSE: impulse,
		DuelEventKeys.TANGENTIAL_IMPULSE: manifold.tangent_impulse[primary],
		DuelEventKeys.ENERGY: energy,
		DuelEventKeys.FRACTION_0: fraction_a,
		DuelEventKeys.FRACTION_1: fraction_b,
		DuelEventKeys.STEEL_PAIR: manifold.pair[primary],
		DuelEventKeys.POINT_COUNT: points,
		DuelEventKeys.INTENSITY: SwingSemantics.clash_intensity(energy, rules.combat),
		DuelEventKeys.CONTACT_CLASS: String(classify(closing, rules)),
		DuelEventKeys.MATERIAL_0: String(spec_a.weapon.material.id),
		DuelEventKeys.MATERIAL_1: String(spec_b.weapon.material.id),
		## The geometry of the clash, carried: the normal the blades met along
		## and the direction the striking point was travelling. Without these a
		## consumer has to rebuild the contact from fighter positions, which is
		## a guess that silently disagrees with the resolver.
		DuelEventKeys.NORMAL_X: nx,
		DuelEventKeys.NORMAL_Y: ny,
		DuelEventKeys.STRIKE_X: tangent_a[0] if attacker != 1 else tangent_b[0],
		DuelEventKeys.STRIKE_Y: tangent_a[1] if attacker != 1 else tangent_b[1],
		DuelEventKeys.ARRESTED_0: outcome.arrested[0],
		DuelEventKeys.ARRESTED_1: outcome.arrested[1],
		DuelEventKeys.DELTA_0: deltas[0],
		DuelEventKeys.DELTA_1: deltas[1],
		DuelEventKeys.IMPULSE_X: outcome.impulse_x,
		DuelEventKeys.IMPULSE_Y: outcome.impulse_y,
		DuelEventKeys.CLOSING_AFTER: outcome.closing_after,
		DuelEventKeys.FRICTION_SATURATION: outcome.friction_saturation,
		DuelEventKeys.PROGRESS_BEFORE: outcome.attack_progress_before,
		DuelEventKeys.PROGRESS_AFTER: outcome.attack_progress_after,
	}))
	## Two readings of the one solve (CONTACT-OUTCOME-001), never two physics
	## paths. A parry is physical interception (PARRY-001): protective steel
	## took a positive impulse and the cut no longer progresses (`arrests`). A
	## redirection that did not arrest a cut on the line is only marked here:
	## whether it was a deflection is what the attack then did — it becomes one
	## when the attack ends having struck nothing (DEFLECTION-001,
	## `WeaponSystem`). A cut that carries on and lands is neither.
	if attacker == DuelEvent.NONE:
		return
	## Only steel that protects its wielder defends (DEFENSE-ROLE-001): the
	## defender's blade, or its guard root when the contact named it — whether
	## either counts is the weapon's authored reading.
	var defender_weapon := rules.spec_of(state.opponent_of(attacker)).weapon
	var protective := defender_weapon.crossguard_protects if _on_defenders_guard(manifold.pair[primary], 1 - attacker) else defender_weapon.blade_protects
	var striker := state.fighter(attacker)
	if first_contact and outcome.redirects(protective):
		striker.weapon.deflection_pending = true
	if not outcome.parries(protective):
		return
	## The riposte advantage is a separate tactical reading of the state the
	## parry left — it may be zero or negative: a parry need not win the
	## tempo, and nothing reads it back.
	var defender := state.opponent_of(attacker)
	var advantage := InitiativeModel.time_to_threat(striker, defender, rules) - InitiativeModel.time_to_threat(defender, striker, rules)
	events.append(DuelEvent.create(DuelEventTypes.PARRY, tick, defender.slot, striker.slot, {DuelEventKeys.MARGIN: advantage, DuelEventKeys.X: px, DuelEventKeys.Y: py}))


## A sword's first impact on stage structures (STRUCTURE-CONTACT-001), solved
## on the points the sweep recorded at its time of impact. It blocks: the
## impulse goes through the sword's lever and the wielder's body only, a swing
## it actually stops ends by the one arrest law, and the sword's impact
## authority dips from its own Δθ̇ like any hard impact (IMPACT-AUTHORITY-001).
## It is never a hit, never a parry, and never opponent contact.
static func _resolve_structure(
	state: MatchState,
	rules: DuelRules,
	slot: int,
	tick: int,
	toi: float,
	events: Array[DuelEvent],
	lcp: ContactLcp,
	scratches: Array[FighterTickScratch]
) -> void:
	var fighter := state.fighter(slot)
	var spec := rules.combatant(slot)
	var contact := state.structure_contacts[slot]
	var points := contact.point_count
	if points == 0:
		return
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	var closing_rows := PackedFloat64Array()
	closing_rows.resize(points)
	var pairs: Array[ContactPair] = []
	var closing := -INF
	for i in points:
		pairs.append(rules.structure_pair(slot, StructureContactSet.structure_of(contact.feature[i])))
		closing = maxf(closing, StructureContactSolver.closing_speed(fighter, pose, contact.point_x[i], contact.point_y[i], contact.point_nx[i], contact.point_ny[i]))
	if closing <= 0.0:
		return
	var inertia := ContactMechanics.weapon_inertia(pose, spec)
	var inverse_mass := ContactMechanics.body_inverse_mass(spec)
	var swinging := CombatPhase.is_swinging(fighter.weapon.phase)
	var progress_before := fighter.weapon.speed * fighter.weapon.swing_dir
	var energy_before := StructureContactSolver.kinetic_energy(fighter, inertia, inverse_mass)
	var delta := PackedFloat64Array([0.0])
	var impulse := StructureContactSolver.solve(contact, fighter, pose, pairs, inertia, inverse_mass, delta, closing_rows, lcp)
	var energy := maxf(energy_before - StructureContactSolver.kinetic_energy(fighter, inertia, inverse_mass), 0.0)
	var primary := 0
	for i in range(1, points):
		if contact.normal_impulse[i] - contact.normal_impulse[primary] > EVEN_SPLIT * impulse:
			primary = i
	if impulse > 0.0:
		var next := ImpactAuthority.after_episode(fighter.impact_authority, delta[0], spec.weapon.swing_speed_full, rules.combat.impact_authority_floor)
		if next < fighter.impact_authority and slot < scratches.size():
			scratches[slot].authority_dipped = true
		fighter.impact_authority = next
	var arrested := false
	if swinging:
		arrested = _interrupt_if_arrested(state, slot, rules, delta[0], scratches)
	events.append(DuelEvent.create(DuelEventTypes.BLADE_STRUCTURE_CONTACT, tick, slot, DuelEvent.NONE, {
		DuelEventKeys.X: contact.point_x[primary],
		DuelEventKeys.Y: contact.point_y[primary],
		DuelEventKeys.NORMAL_X: contact.point_nx[primary],
		DuelEventKeys.NORMAL_Y: contact.point_ny[primary],
		DuelEventKeys.CLOSING_SPEED: closing,
		DuelEventKeys.IMPULSE: impulse,
		DuelEventKeys.TANGENTIAL_IMPULSE: contact.tangent_impulse[primary],
		DuelEventKeys.ENERGY: energy,
		DuelEventKeys.FRACTION_0: contact.fraction[primary],
		DuelEventKeys.POINT_COUNT: points,
		DuelEventKeys.STRUCTURE: StructureContactSet.structure_of(contact.feature[primary]),
		DuelEventKeys.FEATURE: contact.feature[primary],
		DuelEventKeys.MATERIAL_0: String(pairs[primary].a.id),
		DuelEventKeys.MATERIAL_1: String(pairs[primary].b.id),
		DuelEventKeys.CONTACT_CLASS: String(classify(closing, rules)),
		DuelEventKeys.ARRESTED_0: arrested,
		DuelEventKeys.DELTA_0: delta[0],
		DuelEventKeys.PROGRESS_BEFORE: progress_before,
		DuelEventKeys.PROGRESS_AFTER: fighter.weapon.speed * fighter.weapon.swing_dir,
		DuelEventKeys.TOI: toi,
	}))


## Whether a contact of `pair` was on the guard of sword `defender`.
static func _on_defenders_guard(pair: int, defender: int) -> bool:
	return (pair == SwordContactSet.PAIR_BLADE_ON_GUARD and defender == 1) or (pair == SwordContactSet.PAIR_GUARD_ON_BLADE and defender == 0)


## Whether `slot`'s cut in flight reaches the opponent's body with its own
## remaining sweep (THREAT-001, unopposed, no new footwork): the cut's line,
## as a reading.
static func _cut_threatens(state: MatchState, rules: DuelRules, slot: int) -> bool:
	var fighter := state.fighter(slot)
	var opponent := state.opponent_of(slot)
	return InitiativeModel.estimate(fighter, rules.spec_of(fighter), opponent, rules.spec_of(opponent), rules.combat, ThreatEstimate.new(), ThreatContinuation.planted()).within_horizon


## Fill `outcome` from the finished solve: the impulses on the manifold, the
## velocity changes against the pre-solve root velocities, the rows' closing
## after the solve. Reads only; changes nothing.
static func _read_outcome(
	outcome: ContactOutcome,
	manifold: SwordContactSet,
	a: FighterState,
	b: FighterState,
	pose_a: BladePose,
	pose_b: BladePose,
	root_vx: PackedFloat64Array,
	root_vy: PackedFloat64Array,
	deltas: PackedFloat64Array,
	rules: DuelRules
) -> void:
	outcome.closing_after = -INF
	for i in outcome.point_count:
		var jn := manifold.normal_impulse[i]
		var jt := manifold.tangent_impulse[i]
		var nx := manifold.point_nx[i]
		var ny := manifold.point_ny[i]
		outcome.normal_impulse += jn
		outcome.tangent_impulse += jt
		## The tangent is the normal turned +90° (`SwordContactSolver`).
		outcome.impulse_x += jn * nx - jt * ny
		outcome.impulse_y += jn * ny + jt * nx
		var mu := rules.blade_pair().friction
		if mu > 0.0 and jn > 0.0:
			outcome.friction_saturation = maxf(outcome.friction_saturation, absf(jt) / (mu * jn))
		outcome.closing_after = maxf(outcome.closing_after, SwordContactSolver.closing_speed(a, b, pose_a, pose_b, manifold.point_x[i], manifold.point_y[i], nx, ny))
	outcome.delta_vx[0] = a.vx - root_vx[0]
	outcome.delta_vy[0] = a.vy - root_vy[0]
	outcome.delta_vx[1] = b.vx - root_vx[1]
	outcome.delta_vy[1] = b.vy - root_vy[1]
	outcome.delta_weapon_speed[0] = deltas[0]
	outcome.delta_weapon_speed[1] = deltas[1]


## A held contact blocked a driven swing (RIGID-CONTACT-001): a cut that stops
## on a body or a blade ends there instead of pressing forever. The same law
## as a first impact (`arrests`). `deltas` is each sword's weapon-speed change
## from the hold. A hold by itself never changes the phase; only what it did to
## the cut's progress can. `contacted` marks each sword whose hold pressed on
## the opponent (`RigidContactSolver.opponent_contact`): the attack met
## something, so its end is never a whiff.
static func interrupt_held_swings(state: MatchState, rules: DuelRules, deltas: PackedFloat64Array, contacted: PackedByteArray, scratches: Array[FighterTickScratch] = []) -> void:
	for slot in 2:
		if contacted[slot] != 0:
			state.fighter(slot).weapon.attack_contacted = true
		if CombatPhase.is_swinging(state.fighter(slot).weapon.phase):
			_interrupt_if_arrested(state, slot, rules, deltas[slot], scratches)


## Did a contact that changed a cut's speed by `delta` (rad/s) arrest it? One
## law for a first impact and a held contact (RIGID-CONTACT-002), both of:
##
## ```text
## opposed    the contact took progress away     Δθ̇·dir < 0
## arrested   stopped or reversed                θ̇·dir ≤ 0
##            or pinned: under control and       θ̇·dir ≤ control_speed
##            gained nothing over the tick       θ̇·dir ≤ θ̇_start·dir
## ```
##
## The attack phase describes what the sword actually did. A blade a contact
## has brought down to the wielder's `control_speed` — the same speed that
## lets a new attack start and ends a recovery (RECOVERY-001) — is no longer
## swinging through anything once its motor can no longer gain on the contact:
## held under control and no faster than it began the tick, the wielder is
## pressing it, and the cut is over. A cut accelerating out of a contact it
## began in — a fresh launch from a bind is under control on its first tick —
## is still a cut, and so is one travelling faster than control. A contact
## that pushes the sword along its cut never ends it. No ratio and no timer:
## how long a contact lasts is never part of the law, so persistence is not
## interruption — but a cut pinned against a body that only creeps as the
## body yields is arrested, never pressed forever. `start_speed` is the
## blade's speed at the start of the tick (`FighterTickScratch`).
static func arrests(weapon: WeaponState, delta: float, control_speed: float, start_speed: float) -> bool:
	if -delta * weapon.swing_dir <= 0.0:
		return false
	var progress := weapon.speed * weapon.swing_dir
	return progress <= 0.0 or (progress <= control_speed and progress <= start_speed * weapon.swing_dir)


## Interrupt `slot`'s swing into recovery when the contact arrested it;
## returns whether it did. Changes the phase only, never a velocity.
## Without a tick scratch (a hand-built contact) the tick began at the speed the
## contact met.
static func _interrupt_if_arrested(state: MatchState, slot: int, rules: DuelRules, delta: float, scratches: Array[FighterTickScratch] = []) -> bool:
	var fighter := state.fighter(slot)
	var start := scratches[slot].weapon_start_speed if scratches.size() > slot else fighter.weapon.speed - delta
	if not arrests(fighter.weapon, delta, rules.spec_of(fighter).weapon.control_speed, start):
		return false
	WeaponSystem.begin_recovery(fighter, rules)
	return true


## Apply one strike. Every consequence is driven by the physical quantity that
## actually causes it (PHYS-004): severity injures, impulse displaces and
## unbalances, and exposure is a reading that modifies nothing (PHYS-004).
##
## PHYS-010: Bilateral sword-body impulse. One authoritative J computed from
## the contact's inverse effective mass k = 1/m_T + 1/m_A + c²/M_θ, both
## bodies at their real mass (ContactMechanics, IMPACT-PHYSICS-001). Target
## linear, attacker linear, and sword angular reactions are all derived from
## that single J, for every classification: a point driven along its blade
## has almost no lever, so its sword barely turns; one met off its axis is
## deflected. Lethal contacts apply a reduced fraction of the blocking impulse
## before releasing the nonpenetration constraint.
static func _apply_strike(state: MatchState, strike: StrikeResult, rules: DuelRules, tick: int, events: Array[DuelEvent], scratches: Array[FighterTickScratch] = []) -> void:
	var impact := strike.impact
	var attacker := state.fighter(strike.attacker)
	var target := state.fighter(strike.target)
	target.health = maxf(0.0, target.health - strike.damage)
	## Bilateral impulse (PHYS-010): the contact's own solved impulse.
	var weapon_moi := impact.weapon_inertia
	var bilateral_j := impact.impulse
	## A landed hit is opponent contact: the attack's end is never a whiff.
	if bilateral_j > 0.0 or strike.damage > 0.0:
		attacker.weapon.attack_contacted = true
		attacker.weapon.deflection_pending = false
	## Lethal contacts apply only a fraction of the full blocking impulse.
	if strike.lethal:
		bilateral_j *= rules.combat.penetration_resistance_fraction
	## Target linear reaction: pushed away from the blade.
	if impact.target_mass > SimMath.EPSILON:
		var dv_target := bilateral_j / impact.target_mass
		target.vx += impact.normal_x * dv_target
		target.vy += impact.normal_y * dv_target
	## Attacker linear reaction: pushed back by Newton's third law.
	if impact.attacker_mass > SimMath.EPSILON:
		var dv_attacker := bilateral_j / impact.attacker_mass
		attacker.vx -= impact.normal_x * dv_attacker
		attacker.vy -= impact.normal_y * dv_attacker
	## Sword angular reaction: derived from the same J through the same lever.
	## A body that stopped or reversed the cut ends it by the same arrest law
	## as a blade or a hold (RIGID-CONTACT-002) — phase only.
	if weapon_moi > SimMath.EPSILON:
		var turn := -bilateral_j * impact.lever_cross / weapon_moi
		attacker.weapon.speed += turn
		## A torso entry is damage and a blade reaction. It is not an impact-
		## authority episode (IMPACT-AUTHORITY-001 is steel only).
		if CombatPhase.is_swinging(attacker.weapon.phase):
			_interrupt_if_arrested(state, strike.attacker, rules, turn, scratches)
	## Advance weapon-body lifecycle: nonlethal → CONSTRAINING, lethal → PENETRATING.
	state.weapon_body_contacts[strike.attacker].advance_after_entry(strike.lethal)
	var push := 0.0
	if impact.target_mass > SimMath.EPSILON:
		push = bilateral_j / impact.target_mass
	var payload := strike.to_payload()
	payload[DuelEventKeys.PUSH] = push
	payload[DuelEventKeys.HEALTH] = target.health
	payload[DuelEventKeys.REGION] = DuelEventKeys.REGION_TORSO
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
		## The body is thrown along the killing impulse; a run-through holds
		## it on the blade before it lies (FallenBodyState).
		var point := strike.contact_kind == StrikeResult.ContactKind.POKE or strike.contact_kind == StrikeResult.ContactKind.THRUST
		var settle := rules.combat.fallen_settle_ticks_point if point else rules.combat.fallen_settle_ticks_cut
		WeaponSystem.kill(target, strike.toi, SimMath.arctan2(impact.normal_y, impact.normal_x), settle)
		events.append(DuelEvent.create(DuelEventTypes.FIGHTER_KILLED, tick, attacker.slot, target.slot, {DuelEventKeys.X: target.x, DuelEventKeys.Y: target.y}))
	elif strike.stagger_pressure >= rules.spec_of(attacker).weapon.stagger_impulse:
		var striking := rules.spec_of(attacker).weapon
		var ticks := striking.stagger_base_ticks + roundi(striking.stagger_scale_ticks * strike.stagger_pressure)
		WeaponSystem.stagger(target, ticks)
		events.append(DuelEvent.create(DuelEventTypes.STAGGERED, tick, target.slot, attacker.slot, {DuelEventKeys.TICKS: ticks}))
