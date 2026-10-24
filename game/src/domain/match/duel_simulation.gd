class_name DuelSimulation
extends RefCounted

## The authoritative duel. `step` consumes exactly one PlayerCommand per
## fighter per tick and returns the events that tick produced. It never reads
## render delta, Godot physics, input devices, or the identity of the command
## source (COMBAT §7, §69): the same rules + seed + commands always reproduce
## the same duel, whether a human, the CPU, a replay, or a server sent them.
##
## The canonical tick order is versioned and documented, because "when" is as
## much a rule as "what". Changing the order changes the game, so
## `TICK_ORDER_VERSION` must be bumped deliberately alongside
## `/docs/concepts/simulation.md`.
##
## Symmetric by construction: per-fighter updates read only start-of-tick
## relationships, so slot order cannot bias outcomes. Never update fighter A
## and then fighter B against A's already-advanced state.
##
##   1. guard: a finished match accepts no further steps
##   2. dispatch on match phase
##   3. ROUND_ACTIVE: advance phase and round counters
##   4. freeze condition for both fighters (from start-of-tick health and
##      stamina, CONDITION-001, STAMINA-004): scales and stamina gates
##   5. capture start poses for both fighters
##   6. consume attack input edges for both fighters
##   7. compute tracking multipliers from start-of-tick state
##   8. facing then footwork for both fighters
##   9. weapon motor and weapon phase for both fighters
##  10. arena boundary confinement only (body separation shares the TOI loop)
##  11. capture finish poses for both fighters
##  12. contacts (RIGID-CONTACT-001, COMBAT-007):
##      a. persisted sword contacts touching at the start remove their
##         closing speed (RigidContactSolver velocity stage), then the tick
##         is carried again
##      b. unified chronological contact loop (blade↔blade, blade↔structure,
##         blade→body, body↔body, persisted pairs re-touching — inside one
##         substep in that order; body separation resolved
##         inside the same TOI chronology;
##         once the re-hold budget is spent the remainder is carried in sweep
##         substeps with overlap pushed out after each, CONTACT-FALLBACK-001)
##      c. persisted overlap beyond contact_slop pushed out (position stage,
##         bodies kept apart in the same block)
##  13. contact lifecycle upkeep (blade manifold + weapon-body + structures)
##  14. impact authority recovers toward 1, except a sword this tick's steel
##      episode dipped (IMPACT-AUTHORITY-001)
##  15. settle stamina once from the motors' own work over the tick (measured
##      in steps 8–9, before any contact) and a dash start (STAMINA-004)
##  16. round end evaluation
##  17. advance the tick counter
##  18. validate invariants; fail closed on violation
##
## Implements: /spec/invariants.md#sim-001
## Implements: /spec/invariants.md#combat-008
## See also: /docs/concepts/simulation.md

## Bump deliberately when the sequence above changes.
## 15 (rules 53) added the stamina settle after contacts. 16 (rules 57)
## inserts impact-authority recovery between contact lifecycle and that
## settle. Rules 56 kept 15: the dip stayed inside the contact step, and
## authority did not recover until the round reset.
const TICK_ORDER_VERSION := 16

var rules: DuelRules
## Contact-cap counters for this simulation (never hashed, never read back).
var diagnostics := ContactDiagnostics.new()
var _collision := CollisionSystem.new()
## Persistent normal constraint (RIGID-CONTACT-001). A seam: tests substitute
## an inert or audited solver to prove what the constraint does and does not
## touch; production never replaces it.
var rigid_solver := RigidContactSolver.new()
var _report := ContactReport.new()
var _start: Array[FighterPose] = [FighterPose.new(), FighterPose.new()]
var _finish: Array[FighterPose] = [FighterPose.new(), FighterPose.new()]
## Poses just after a contact resolved, where the carried remainder starts.
var _impact: Array[FighterPose] = [FighterPose.new(), FighterPose.new()]
var _scratch: Array[FighterTickScratch] = [FighterTickScratch.new(), FighterTickScratch.new()]
var _healthy := ConditionState.healthy()
## Each combatant's reference energies for stamina (footwork, heading, blade),
## derived once from its own physics (STAMINA-004). Three scalars: a vector
## would be a tuple of unrelated energies.
var _move_reference := PackedFloat64Array([0.0, 0.0])
var _turn_reference := PackedFloat64Array([0.0, 0.0])
var _swing_reference := PackedFloat64Array([0.0, 0.0])


func _init() -> void:
	_collision.diagnostics = diagnostics
	rigid_solver.diagnostics = diagnostics


## Returns null when the rules are invalid (fail closed).
static func create(duel_rules: DuelRules) -> DuelSimulation:
	if duel_rules == null or not duel_rules.is_valid():
		return null
	var simulation := DuelSimulation.new()
	simulation.rules = duel_rules
	for slot in 2:
		var spec := duel_rules.combatant(slot)
		simulation._move_reference[slot] = StaminaModel.move_reference(spec.fighter)
		simulation._turn_reference[slot] = StaminaModel.turn_reference(spec.fighter)
		simulation._swing_reference[slot] = StaminaModel.swing_reference(spec)
	return simulation


func new_match(seed_value: int) -> MatchState:
	return DuelSetup.new_state(rules, seed_value)


func step(state: MatchState, command_0: PlayerCommand, command_1: PlayerCommand) -> Array[DuelEvent]:
	var events: Array[DuelEvent] = []
	if state.is_finished():
		return events
	match state.phase:
		MatchPhase.Id.ROUND_INTRO:
			_step_intro(state, events)
		MatchPhase.Id.ROUND_ACTIVE:
			_step_active(state, command_0.sanitized(), command_1.sanitized(), events)
		MatchPhase.Id.POST_ROUND_FREE:
			_step_post_round_free(state, command_0.sanitized(), command_1.sanitized(), events)
		MatchPhase.Id.ROUND_RESULT:
			_step_result(state, command_0.sanitized(), command_1.sanitized(), events)
	state.tick += 1
	var violation := StateInvariants.check(state, rules)
	if violation != StateInvariants.OK:
		_fail_closed(state, violation, events)
	return events


## Authoritative state left its legal set. There is no sound way to continue
## from an impossible state, and quietly repairing it would hide the defect
## and desynchronize a replay, so the match becomes a no-contest.
func _fail_closed(state: MatchState, violation: StringName, events: Array[DuelEvent]) -> void:
	events.append(DuelEvent.create(
		DuelEventTypes.SIMULATION_FAULT,
		state.tick,
		DuelEvent.NONE,
		DuelEvent.NONE,
		{DuelEventKeys.INVARIANT: String(violation)}
	))
	_end_match(state, MatchPhase.DRAW, MatchPhase.REASON_NO_CONTEST, events)


func _step_intro(state: MatchState, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	if state.phase_ticks >= rules.intro_ticks:
		state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
		for fighter in state.fighters:
			fighter.clear_attack_input()
		events.append(DuelEvent.create(DuelEventTypes.ROUND_STARTED, state.tick, DuelEvent.NONE, DuelEvent.NONE, {DuelEventKeys.ROUND: state.round_number}))


func _step_active(state: MatchState, command_0: PlayerCommand, command_1: PlayerCommand, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	state.round_ticks += 1
	var tick := state.tick
	var a := state.fighter(0)
	var b := state.fighter(1)
	var commands: Array[PlayerCommand] = [command_0, command_1]
	## Condition is frozen once per fighter, from start-of-tick health, before
	## any motor runs (CONDITION-001): every system reads the same state and
	## nothing recomputes it mid-tick.
	for slot in 2:
		var starting := state.fighter(slot)
		var scratch := _scratch[slot]
		_freeze_condition(starting, scratch)
		scratch.weapon_start_speed = starting.weapon.speed
		scratch.start_vx = starting.vx
		scratch.start_vy = starting.vy
		scratch.start_turn_rate = starting.turn_rate
		scratch.exertion = 0.0
		scratch.dashed = false
		scratch.authority_dipped = false
	_start[0].write(a, rules.combatant(0))
	_start[1].write(b, rules.combatant(1))
	for slot in 2:
		WeaponSystem.apply_input(state.fighter(slot), commands[slot], rules, tick, events)
	## Each combat heading catches its target bearing at the authority its
	## commitment leaves (HEADING-001). Read for both before either turns.
	var tracking := PackedFloat64Array([
		CommitmentModel.turn_torque_share(a, rules.combatant(0), _scratch[0].condition, rules.combat),
		CommitmentModel.turn_torque_share(b, rules.combatant(1), _scratch[1].condition, rules.combat),
	])
	var rate_tracking := PackedFloat64Array([
		CommitmentModel.turn_rate_share(a, rules.combatant(0), _scratch[0].condition, rules.combat),
		CommitmentModel.turn_rate_share(b, rules.combatant(1), _scratch[1].condition, rules.combat),
	])
	## Each fighter's opponent where it stands now, read once: the heading
	## turns toward it, never the footwork. Footwork runs in each fighter's
	## own combat frame, its heading at the start of the tick, read before any
	## heading turns (MOVEMENT-FRAME-001, FRICTION-ORDER-001).
	var targets := PackedFloat64Array([b.x, b.y, a.x, a.y])
	var frames := PackedFloat64Array([SimMath.heading_cosine(a.facing), SimMath.heading_sine(a.facing), SimMath.heading_cosine(b.facing), SimMath.heading_sine(b.facing)])
	for slot in 2:
		var fighter := state.fighter(slot)
		var body := rules.combatant(slot).fighter
		if fighter.is_alive():
			var condition := _scratch[slot].condition
			## The shares already carry the wound (RESPONSIVE-COMMITMENT-001), so
			## the heading motor takes them as final.
			FacingSystem.step(fighter, targets[slot * 2], targets[slot * 2 + 1], tracking[slot], body, null, rate_tracking[slot])
			var burst := MovementSystem.step_in_frame(fighter, frames[slot * 2], frames[slot * 2 + 1], commands[slot].axis_x(), commands[slot].axis_y(), tick, body, condition, commands[slot].dash_modifier)
			_measure_body_work(fighter, body, slot)
			if burst != MovementGestureState.BurstKind.NONE:
				_scratch[slot].dashed = true
				events.append(
					DuelEvent.create(
						DuelEventTypes.BURST_STARTED,
						tick,
						slot,
						DuelEvent.NONE,
						{
							DuelEventKeys.BURST: int(burst),
							DuelEventKeys.HEADING_X: fighter.gesture.burst_dir_x,
							DuelEventKeys.HEADING_Y: fighter.gesture.burst_dir_y,
						}
					)
				)
		else:
			MovementSystem.coast(fighter, body)
	for slot in 2:
		WeaponSystem.step(state.fighter(slot), rules, tick, events, _scratch[slot].condition, _scratch[slot], _guard_return_scale(state, slot), diagnostics)
		_measure_blade_work(state.fighter(slot), slot)
	## Step 10: support. An open edge rings out at `platform_radius`. A closed
	## edge holds the centre on the support circle and removes outward speed
	## only there.
	## Body separation shares the TOI chronology (COMBAT-007) rather than
	## running before sword contacts, because a separation pass can move a
	## fighter away from a sword tip and erase a stab that chronologically
	## preceded the body overlap.
	for slot in 2:
		var fighter := state.fighter(slot)
		if fighter.is_alive() and not fighter.is_falling:
			if rules.is_closed_edge():
				ArenaConstraints.constrain(fighter, rules)
			else:
				var crossing := ArenaConstraints.detect_edge_crossing(
					_start[slot].x, _start[slot].y, fighter.x, fighter.y, rules.platform_radius
				)
				if crossing >= 0.0:
					fighter.lose_support(crossing)
					events.append(DuelEvent.create(
						DuelEventTypes.RING_OUT, tick, slot, DuelEvent.NONE,
						{
							DuelEventKeys.POSITION_X: fighter.x,
							DuelEventKeys.POSITION_Y: fighter.y,
							DuelEventKeys.VELOCITY_X: fighter.vx,
							DuelEventKeys.VELOCITY_Y: fighter.vy,
							DuelEventKeys.TOI: crossing,
						}
					))
	_finish[0].write(a, rules.combatant(0))
	_finish[1].write(b, rules.combatant(1))
	_resolve_contacts(state, tick, events)
	state.blade_contact.tick()
	state.body_contact.tick()
	for structure_contact in state.structure_contacts:
		structure_contact.tick()
	_recover_impact_authority(state)
	_settle_stamina(state)
	_check_round_end(state, events)


## Footwork and heading work over the tick, from the motors' own output: the
## force or torque each applied times its mid-step velocity (STAMINA-004).
## Read right after the footwork step, before any contact moves the body.
func _measure_body_work(fighter: FighterState, body: FighterDefinition, slot: int) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var scratch := _scratch[slot]
	var move_power := body.mass * (fighter.ax * (scratch.start_vx + fighter.vx) + fighter.ay * (scratch.start_vy + fighter.vy)) * 0.5
	var turn_power := body.moment_of_inertia() * (fighter.turn_rate - scratch.start_turn_rate) / dt * (scratch.start_turn_rate + fighter.turn_rate) * 0.5
	scratch.exertion += StaminaModel.channel(move_power, dt, _move_reference[slot], rules.combat.stamina_move_cost, rules.combat)
	scratch.exertion += StaminaModel.channel(turn_power, dt, _turn_reference[slot], rules.combat.stamina_turn_cost, rules.combat)


## The blade motor's work over the tick: its torque times the blade's
## mid-step speed, read right after the motor, before any contact.
func _measure_blade_work(fighter: FighterState, slot: int) -> void:
	if not fighter.is_alive():
		return
	var scratch := _scratch[slot]
	var power := fighter.weapon.motor_torque * (scratch.weapon_start_speed + fighter.weapon.speed) * 0.5
	scratch.exertion += StaminaModel.channel(power, SimulationTimebase.TICK_SECONDS, _swing_reference[slot], rules.combat.stamina_swing_cost, rules.combat)


## One recovery step toward full impact authority, after the contact dip and
## before stamina. A sword this tick's steel episode already dipped does not
## also recover (IMPACT-AUTHORITY-001). The rate is the guard return's ωn.
func _recover_impact_authority(state: MatchState) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var wn := rules.combat.guard_return_natural_frequency
	for slot in 2:
		if _scratch[slot].authority_dipped:
			continue
		var fighter := state.fighter(slot)
		if not fighter.is_alive():
			continue
		fighter.impact_authority = ImpactAuthority.recover(fighter.impact_authority, wn, dt)


## Settle each living fighter's stamina once (STAMINA-004): this tick's
## capability came from its starting value; the settled one is the next tick's.
func _settle_stamina(state: MatchState) -> void:
	for slot in 2:
		var fighter := state.fighter(slot)
		if fighter.is_alive():
			fighter.stamina = StaminaModel.settle(fighter.stamina, _scratch[slot].exertion, _scratch[slot].dashed, SimulationTimebase.TICK_SECONDS, rules.combat)


## Freeze `fighter`'s condition for this tick into `scratch` (CONDITION-001,
## STAMINA-004).
## A dead body has no voluntary motor: its blade settles under the plain,
## unscaled hold.
func _freeze_condition(fighter: FighterState, scratch: FighterTickScratch) -> void:
	if fighter.is_alive():
		ConditionModel.compute(fighter.health, rules.spec_of(fighter).fighter.max_health, fighter.stamina, rules.combat, scratch.condition)
	else:
		scratch.condition.copy_from(_healthy)


## Resolve every contact in this tick in the order it actually happened.
##
## One contact per tick is not enough, because a blade clash at t = 0.20
## changes whether the body cut at t = 0.34 exists at all. So the tick is
## walked chronologically: find the earliest contact in what remains, rewind
## to that instant, resolve it, carry the rest of the tick forward from the
## *post-impulse* state, and search again. Candidates are never enumerated
## from the original poses and sorted — that would resolve a cut that the
## parry already prevented.
func _resolve_contacts(state: MatchState, tick: int, events: Array[DuelEvent]) -> void:
	var elapsed := 0.0
	var limit := rules.combat.max_contacts_per_tick
	var had_body_push := false
	var resolved := 0
	var holds := RigidContactSolver.HOLDS_PER_TICK
	## A re-hold that finds nothing closing proves the deepening it answered is
	## a fast-turning contact's second-order drift, not motion along the
	## normal: holding again cannot change the trajectory, so the rest of this
	## tick's drift is the position stage's (RIGID-CONTACT-001), and that is
	## not the budget running out.
	var drifting := false
	## Once the budget is spent, the rest of the tick is carried without
	## letting a held contact be driven through (CONTACT-FALLBACK-001).
	var fallback := false
	## What this tick's re-holds held, for the diagnostics' characterization of
	## an exhausted budget (CONTACT-REHOLD-FALLBACK-001); never read by play.
	var reheld := PackedInt32Array()
	var least_rehold := INF
	state.blade_contact.begin_search()
	for lifecycle in state.weapon_body_contacts:
		lifecycle.normal_impulse = 0.0
	_hold_persistent_contacts(state, tick, events)
	## A held contact (persistent) costs no impulse and no event, so it spends
	## its own fixed budget, never the contacts'. Bodies meet once a tick; a
	## later re-overlap is separated where each remainder is carried.
	while resolved < limit:
		_collision.detect(state, _start, _finish, rules, state.blade_contact, _report, holds > 0 and not drifting, not had_body_push)
		if not _report.any():
			_update_body_contact_separation(state, had_body_push)
			_settle_overlap(state, tick, events)
			return
		var held := not _report.any_new()
		if not held:
			resolved += 1
		else:
			holds -= 1
			if holds == 0:
				diagnostics.rehold_budget_exhausted += 1
				fallback = true
		var toi := elapsed + (1.0 - elapsed) * _report.fraction
		if not SimulationGuardrails.validate_toi_monotonicity(elapsed, toi):
			_fail_closed(state, &"toi_regression", events)
			return
		_seek(state, _report.fraction)
		_start[0].write(state.fighter(0), rules.combatant(0))
		_start[1].write(state.fighter(1), rules.combatant(1))
		ContactResolver.resolve(state, _report, rules, tick, toi, events, _scratch, rigid_solver.lcp)
		## Whatever was resolved here changed velocities; every held contact is
		## held again from them before the remainder is carried.
		var solved := rigid_solver.solve_velocity(state, rules)
		if solved > 0.0:
			ContactResolver.interrupt_held_swings(state, rules, rigid_solver.weapon_delta, rigid_solver.opponent_contact, _scratch)
		elif held:
			drifting = true
		if held:
			least_rehold = minf(least_rehold, solved)
			for point in state.blade_contact.point_count:
				if not reheld.has(state.blade_contact.contact_id[point]):
					reheld.append(state.blade_contact.contact_id[point])
			if holds == 0:
				diagnostics.record_rehold_fallback(tick, reheld.size(), least_rehold)
		if _report.body_push:
			had_body_push = true
			if state.body_contact.phase == BodyContactState.Phase.SEPARATED:
				state.body_contact.begin_contact()
		_impact[0].write(state.fighter(0), rules.combatant(0))
		_impact[1].write(state.fighter(1), rules.combatant(1))
		if fallback:
			_carry_without_tunnelling(state, 1.0 - toi)
		else:
			_carry(state, 1.0 - toi)
		## Post-impulse support-loss: contact resolution (body push, knockback)
		## may have carried a fighter past the platform edge. Mark them falling
		## now rather than waiting for the next tick, at the instant their
		## centre actually crossed during the carried remainder — not at the
		## contact's TOI, which is only the earliest it could have happened and
		## would misorder a later same-tick kill (COMBAT-014).
		_check_support(state, tick, events, _impact, toi)
		_finish[0].write(state.fighter(0), rules.combatant(0))
		_finish[1].write(state.fighter(1), rules.combatant(1))
		elapsed = toi
	## Bounded iteration is not optional on a mobile budget. Saturation means
	## the geometry is pathological, so the pair is held in contact — a
	## tunnelled blade would be far worse than a missed impulse.
	state.blade_contact.set_phase(SwordContactSet.Phase.CONTACTING)
	diagnostics.contact_cap_hits += 1
	_update_body_contact_separation(state, had_body_push)
	events.append(DuelEvent.create(DuelEventTypes.CONTACT_SATURATED, tick, DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.COUNT: limit,
	}))
	_settle_overlap(state, tick, events)


## Persisted contacts are constraints before they are motion
## (RIGID-CONTACT-001). The motors have already produced this tick's velocities
## and carried them to the finish poses; rewind to the start, let every
## persisted contact that is touching remove its closing speed, and carry the
## tick again from the constrained velocities. Untouched when nothing closes.
func _hold_persistent_contacts(state: MatchState, tick: int, events: Array[DuelEvent]) -> void:
	_seek(state, 0.0)
	if rigid_solver.solve_velocity(state, rules, true) > 0.0:
		ContactResolver.interrupt_held_swings(state, rules, rigid_solver.weapon_delta, rigid_solver.opponent_contact, _scratch)
		_carry(state, 1.0)
		_check_support(state, tick, events, _start, 0.0)
		_finish[0].write(state.fighter(0), rules.combatant(0))
		_finish[1].write(state.fighter(1), rules.combatant(1))
		return
	for slot in 2:
		var fighter := state.fighter(slot)
		var to := _finish[slot]
		fighter.x = to.x
		fighter.y = to.y
		fighter.facing = to.facing
		fighter.weapon.angle = to.weapon_angle


## End of the contact loop: overlap a persisted contact still carries is pushed
## back to `contact_slop` without touching velocities, so a held blade never
## drifts into what it rests on.
func _settle_overlap(state: MatchState, tick: int, events: Array[DuelEvent]) -> void:
	_impact[0].write(state.fighter(0), rules.combatant(0))
	_impact[1].write(state.fighter(1), rules.combatant(1))
	rigid_solver.project(state, rules)
	_check_support(state, tick, events, _impact, 1.0)


## A fighter carried or pushed past the platform edge loses support at the
## instant their centre crossed on the way from `from` (posed at tick fraction
## `toi`) to where they are now.
func _check_support(state: MatchState, tick: int, events: Array[DuelEvent], from: Array[FighterPose], toi: float) -> void:
	for slot in 2:
		var fighter := state.fighter(slot)
		if fighter.is_alive() and not fighter.is_falling:
			if rules.is_closed_edge():
				ArenaConstraints.constrain(fighter, rules)
				continue
			if SimMath.length(fighter.x, fighter.y) >= rules.platform_radius:
				fighter.lose_support(remainder_crossing(from[slot], fighter, toi, rules.platform_radius))
				events.append(DuelEvent.create(
					DuelEventTypes.RING_OUT, tick, slot, DuelEvent.NONE,
					{
						DuelEventKeys.POSITION_X: fighter.x,
						DuelEventKeys.POSITION_Y: fighter.y,
						DuelEventKeys.VELOCITY_X: fighter.vx,
						DuelEventKeys.VELOCITY_Y: fighter.vy,
						DuelEventKeys.TOI: fighter.support_lost_fraction,
					}
				))


## Check whether the body-body pair has separated after the contact loop.
## If they were in contact but no body push was detected this tick, and the
## gap now exceeds the epsilon, transition to SEPARATED. If they were
## SEPARATED and a push happened, `begin_contact` was already called above.
func _update_body_contact_separation(state: MatchState, had_body_push: bool) -> void:
	if state.body_contact.phase == BodyContactState.Phase.CONTACTING and not had_body_push:
		var a := state.fighter(0)
		var b := state.fighter(1)
		var gap := SimMath.length(b.x - a.x, b.y - a.y) - (rules.combatant(0).fighter.push_radius + rules.combatant(1).fighter.push_radius)
		if gap > rules.combat.body_contact_separation_epsilon:
			state.body_contact.end_contact()


## Rewind both fighters to the pose at sub-interval fraction `s`. Velocities
## are untouched: they are what this tick already settled on, and the contact
## is about to change them.
func _seek(state: MatchState, s: float) -> void:
	for slot in 2:
		var fighter := state.fighter(slot)
		var from := _start[slot]
		var to := _finish[slot]
		fighter.x = SimMath.mix(from.x, to.x, s)
		fighter.y = SimMath.mix(from.y, to.y, s)
		fighter.facing = from.facing + SimMath.wrap_angle(to.facing - from.facing) * s
		fighter.weapon.angle = SimMath.mix(from.weapon_angle, to.weapon_angle, s)


## The tick fraction at which a fighter carried from `impact` (the pose just
## after a contact at `toi`) to `fighter` (the end of the tick) crossed the
## edge. The remainder is the same linear carry `_carry` performs, so the
## crossing is its line–circle intersection, mapped back into the tick. A body
## already past the edge at the contact (a position correction put it there)
## crossed at the contact itself.
static func remainder_crossing(impact: FighterPose, fighter: FighterState, toi: float, radius: float) -> float:
	var share := ArenaConstraints.detect_edge_crossing(impact.x, impact.y, fighter.x, fighter.y, radius)
	return toi + maxf(share, 0.0) * (1.0 - toi)


## Guard return while steel is persisted (any phase but SEPARATED) is the
## authored share; a separated pair returns in full. Either way the fighter's
## impact authority multiplies it (GUARD-RETURN-001, IMPACT-AUTHORITY-001).
func _guard_return_scale(state: MatchState, slot: int) -> float:
	var steel := 1.0
	if state.blade_contact.phase != SwordContactSet.Phase.SEPARATED:
		steel = rules.combat.guard_steel_return_scale
	return steel * state.fighter(slot).impact_authority


## Carry both fighters through the remaining `share` of the tick under their
## post-contact velocities. The motor has already run, so this is the same
## linear integration the systems themselves performed — just over what is
## left of the tick.
func _carry(state: MatchState, share: float) -> void:
	var dt := SimulationTimebase.TICK_SECONDS * share
	for slot in 2:
		var fighter := state.fighter(slot)
		var limit := rules.combatant(slot).weapon.guard_limit
		fighter.x += fighter.vx * dt
		fighter.y += fighter.vy * dt
		fighter.facing = SimMath.compose_angle(fighter.facing, fighter.turn_rate * dt)
		## The guard limit is an inelastic stop, the motor's own law. The
		## remainder has no second soft-zone pass; a speed the stop still has
		## to remove, above one tick of wind-up, is the fallback.
		var into := fighter.weapon.speed
		var angle_before := fighter.weapon.angle
		var spec := rules.combatant(slot)
		var inertia := WeaponKinematics.motor_inertia(spec, angle_before)
		if WeaponSystem.settle_at_stop(fighter.weapon, angle_before + into * dt, limit) and WeaponSystem.is_hard_stop(into, angle_before, true, limit, spec.weapon.windup_accel(spec.fighter.weapon_torque_scale, inertia)):
			diagnostics.guard_hard_stop_hits += 1
	ArenaConstraints.resolve(state.fighter(0), state.fighter(1), rules)


## CONTACT-FALLBACK-001. A tick that has spent its re-hold budget no longer
## lets the sweep catch a held contact being driven deeper, and the position
## stage at the end of the tick only sees where the swords finished — a blade
## carried through the other in one remainder would be cleared on the wrong
## side. So the remainder is carried in the sweep's own substeps (its travel
## metric, capped at `max_substeps`), and after each the position stage pushes
## that substep's overlap back out. The pair keeps its last non-penetrating
## side; only the advance along the contact normal is cancelled; tangent slide
## and every other motion carry on; no velocity is touched, θ̇ included; there is
## no snap and no bind. Bounded, deterministic, counted only as
## `rehold_budget_exhausted`; the next tick starts with a full budget. It is not
## a combat mechanic; representative play reaches it only as the bounded
## fast-slide class (CONTACT-REHOLD-FALLBACK-001).
func _carry_without_tunnelling(state: MatchState, share: float) -> void:
	var dt := SimulationTimebase.TICK_SECONDS * share
	var travel := 0.0
	for slot in 2:
		var fighter := state.fighter(slot)
		travel += SimMath.length(fighter.vx, fighter.vy) * dt
		travel += rules.combatant(slot).weapon.tip_radius * absf(fighter.turn_rate + fighter.weapon.speed) * dt
	var steps := clampi(ceili(travel / rules.combat.substep_travel), 1, rules.combat.max_substeps)
	for _step in steps:
		_carry(state, share / float(steps))
		rigid_solver.project(state, rules)


## Whose commands a tick reads — the one input gate. While a round is fought,
## both fighters' (each tick decides for itself what a dead or falling body can
## still do). Once it is decided, only the round's winner, alive and on the
## platform, keeps control: through the post-round freedom and the whole
## result, until exactly the next round's intro or the end of the match. Every
## other command is ignored.
static func accepts_gameplay_input(state: MatchState, slot: int) -> bool:
	match state.phase:
		MatchPhase.Id.ROUND_ACTIVE:
			return true
		MatchPhase.Id.POST_ROUND_FREE, MatchPhase.Id.ROUND_RESULT:
			var fighter := state.fighter(slot)
			return slot == state.round_winner and fighter.is_alive() and not fighter.is_falling
	return false


## The round is decided; post_round_free_ticks of freedom, then the result.
## Timer expiry → ROUND_RESULT.
func _step_post_round_free(state: MatchState, command_0: PlayerCommand, command_1: PlayerCommand, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	_step_decided(state, command_0, command_1, events)
	if state.phase_ticks >= rules.post_round_free_ticks:
		state.set_phase(MatchPhase.Id.ROUND_RESULT)


## One tick of a decided round, shared by the post-round freedom and the
## result: the winner can walk, dash, charge and swing, and even follow over
## the edge (a presentation easter egg — no score change); everyone else
## coasts to a stop — a killed body slides as a body and can be pushed, turned
## and carried over the edge (`FallenBodySystem`) — and their blade settles,
## its settling events discarded.
func _step_decided(state: MatchState, command_0: PlayerCommand, command_1: PlayerCommand, events: Array[DuelEvent]) -> void:
	var tick := state.tick
	var commands: Array[PlayerCommand] = [command_0, command_1]
	var settling: Array[DuelEvent] = []
	for slot in 2:
		var fighter := state.fighter(slot)
		if accepts_gameplay_input(state, slot):
			var cmd := commands[slot]
			WeaponSystem.apply_input(fighter, cmd, rules, tick, events)
			var opponent := state.opponent_of(slot)
			var body := rules.spec_of(fighter).fighter
			var condition := _scratch[slot].condition
			_freeze_condition(fighter, _scratch[slot])
			var frame_x := SimMath.heading_cosine(fighter.facing)
			var frame_y := SimMath.heading_sine(fighter.facing)
			FacingSystem.step(fighter, opponent.x, opponent.y, 1.0, body, condition)
			MovementSystem.step_in_frame(fighter, frame_x, frame_y, cmd.axis_x(), cmd.axis_y(), tick, body, condition, cmd.dash_modifier)
			WeaponSystem.step(fighter, rules, tick, events, condition, null, _guard_return_scale(state, slot), diagnostics)
			## Winner follow-over-edge easter egg: emit presentation event, no score change.
			## A closed edge holds the winner instead of playing that fall.
			if rules.is_closed_edge():
				ArenaConstraints.constrain(fighter, rules)
			else:
				var crossing := ArenaConstraints.detect_edge_crossing(
					fighter.x - fighter.vx * SimulationTimebase.TICK_SECONDS,
					fighter.y - fighter.vy * SimulationTimebase.TICK_SECONDS,
					fighter.x, fighter.y, rules.platform_radius
				)
				if crossing >= 0.0:
					fighter.lose_support(crossing)
					events.append(DuelEvent.create(DuelEventTypes.POST_ROUND_FALL, tick, slot))
		else:
			if fighter.fallen.active:
				FallenBodySystem.step(fighter, rules, tick, events)
			else:
				MovementSystem.coast(fighter, rules.spec_of(fighter).fighter)
			fighter.clear_attack_input()
			WeaponSystem.step(fighter, rules, tick, settling, null, null, _guard_return_scale(state, slot), diagnostics)
	FallenBodySystem.resolve_bodies(state.fighter(0), state.fighter(1), rules)


## The result: the decided round goes on (`_step_decided`) while it is shown;
## at its end the next round's intro, or the end of the match.
func _step_result(state: MatchState, command_0: PlayerCommand, command_1: PlayerCommand, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	_step_decided(state, command_0, command_1, events)
	if state.phase_ticks < rules.result_ticks:
		return
	var winner := MatchOutcome.set_winner(state.scores, state.round_number, rules)
	if winner != MatchPhase.NO_WINNER:
		_end_match(state, winner, MatchOutcome.reason(state.scores, rules), events)
	else:
		state.round_number += 1
		DuelSetup.reset_round(state, rules)
		state.set_phase(MatchPhase.Id.ROUND_INTRO)


func _check_round_end(state: MatchState, events: Array[DuelEvent]) -> void:
	var a_out := state.fighter(0).terminal_kind()
	var b_out := state.fighter(1).terminal_kind()
	var timed_out := state.round_ticks >= rules.round_time_limit_ticks
	if a_out == FighterState.Terminal.NONE and b_out == FighterState.Terminal.NONE and not timed_out:
		return
	var winner := MatchPhase.DRAW
	var reason := MatchPhase.REASON_KILL
	## COMBAT-014: a fighter leaves the round at their terminal instant — the
	## earlier of a lethal blow and a lost footing — and the one who left
	## first loses. The reason is the loser's way out.
	if a_out != FighterState.Terminal.NONE and b_out != FighterState.Terminal.NONE:
		winner = _trade_winner(state)
		if winner == MatchPhase.DRAW:
			reason = MatchPhase.REASON_RING_OUT if a_out == FighterState.Terminal.RING_OUT and b_out == FighterState.Terminal.RING_OUT else MatchPhase.REASON_DOUBLE_KILL
		elif state.fighter(1 - winner).terminal_kind() == FighterState.Terminal.RING_OUT:
			reason = MatchPhase.REASON_RING_OUT
		else:
			reason = MatchPhase.REASON_TRADE_FIRST_CONTACT
	elif a_out != FighterState.Terminal.NONE:
		winner = 1
		reason = MatchPhase.REASON_RING_OUT if a_out == FighterState.Terminal.RING_OUT else MatchPhase.REASON_KILL
	elif b_out != FighterState.Terminal.NONE:
		winner = 0
		reason = MatchPhase.REASON_RING_OUT if b_out == FighterState.Terminal.RING_OUT else MatchPhase.REASON_KILL
	else:
		reason = MatchPhase.REASON_TIMEOUT
		var health_a := state.fighter(0).health
		var health_b := state.fighter(1).health
		if health_a != health_b:
			winner = 0 if health_a > health_b else 1
	state.round_winner = winner
	state.end_reason = reason
	if winner == 0 or winner == 1:
		state.scores[winner] += 1
	## Transition to POST_ROUND_FREE for winner celebration, then ROUND_RESULT.
	state.set_phase(MatchPhase.Id.POST_ROUND_FREE)
	events.append(DuelEvent.create(DuelEventTypes.ROUND_ENDED, state.tick, winner if winner != MatchPhase.DRAW else DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.ROUND: state.round_number,
		DuelEventKeys.WINNER: winner,
		DuelEventKeys.REASON: String(reason),
		DuelEventKeys.SCORE_0: state.scores[0],
		DuelEventKeys.SCORE_1: state.scores[1],
	}))


## Both fighters fell this tick. Decide it on the only thing that can honestly
## decide it: which blade arrived first (COMBAT §58).
##
## A mutual kill is not automatically a draw. Blades reach at measurable
## instants, and a fighter who was already down when the return cut landed did
## not trade — they lost the exchange and then their body followed through. An
## exact tie genuinely has nothing to separate it and stays a draw.
##
## Slot number, attacker/defender role, remaining health, and randomness are
## all deliberately absent: any of them would make the arena asymmetric.
func _trade_winner(state: MatchState) -> int:
	var a := state.fighter(0).terminal_time()
	var b := state.fighter(1).terminal_time()
	if a < b:
		return 1
	if b < a:
		return 0
	return MatchPhase.DRAW


func _end_match(state: MatchState, winner: int, reason: StringName, events: Array[DuelEvent]) -> void:
	state.match_winner = winner
	state.end_reason = reason
	state.set_phase(MatchPhase.Id.MATCH_ENDED)
	events.append(DuelEvent.create(DuelEventTypes.MATCH_ENDED, state.tick, winner if winner != MatchPhase.DRAW else DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.WINNER: winner,
		DuelEventKeys.REASON: String(reason),
		DuelEventKeys.SCORE_0: state.scores[0],
		DuelEventKeys.SCORE_1: state.scores[1],
		DuelEventKeys.ROUNDS: state.round_number,
	}))
