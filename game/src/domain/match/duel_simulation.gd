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
##   4. freeze capability for both fighters (from start-of-tick stamina)
##   5. capture start poses for both fighters
##   6. consume attack input edges for both fighters
##   7. compute tracking multipliers from start-of-tick state
##   8. facing then footwork for both fighters (writes turn/movement exertion)
##   9. weapon motor and weapon phase for both fighters (writes weapon exertion)
##  10. arena boundary confinement only (body separation shares the TOI loop)
##  11. capture finish poses for both fighters
##  12. bind upkeep
##  13. unified chronological contact loop (blade↔blade, blade→body, body↔body;
##      body separation resolved inside the same TOI chronology; writes
##      contact_shock to scratch; PHYS-008 asymmetric coupling)
##  14. stamina step: drain from scratch work, recovery if below threshold,
##      apply contact shock, clamp
##  15. contact pair lifecycle upkeep (blade + weapon-body)
##  16. round end evaluation
##  17. advance the tick counter
##  18. validate invariants; fail closed on violation
##
## Implements: /spec/invariants.md#sim-001
## Implements: /spec/invariants.md#combat-008
## See also: /docs/concepts/simulation.md

## Bump deliberately when the sequence above changes.
const TICK_ORDER_VERSION := 7

var rules: DuelRules
var _collision := CollisionSystem.new()
var _report := ContactReport.new()
var _start: Array[FighterPose] = [FighterPose.new(), FighterPose.new()]
var _finish: Array[FighterPose] = [FighterPose.new(), FighterPose.new()]
var _scratch: Array[FighterTickScratch] = [FighterTickScratch.new(), FighterTickScratch.new()]


## Returns null when the rules are invalid (fail closed).
static func create(duel_rules: DuelRules) -> DuelSimulation:
	if duel_rules == null or not duel_rules.is_valid():
		return null
	var simulation := DuelSimulation.new()
	simulation.rules = duel_rules
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
		MatchPhase.Id.ROUND_RESULT:
			_step_result(state, events)
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
	_scratch[0].reset()
	_scratch[1].reset()
	_start[0].write(a)
	_start[1].write(b)
	for slot in 2:
		WeaponSystem.apply_input(state.fighter(slot), commands[slot], rules, tick, events)
	var tracking := PackedFloat64Array([
		CommitmentModel.tracking_multiplier(a, b, rules.fighter),
		CommitmentModel.tracking_multiplier(b, a, rules.fighter),
	])
	var targets := PackedFloat64Array([b.x, b.y, a.x, a.y])
	for slot in 2:
		var fighter := state.fighter(slot)
		if fighter.is_alive():
			var stamina_max := StaminaModel.max_for_health(fighter.health, rules.fighter.max_health, rules.fighter.base_stamina, rules.combat)
			var turn_cap := CapabilityModel.resolve_turn(fighter.health, rules.fighter.max_health, fighter.stamina, stamina_max, rules.combat)
			var move_cap := CapabilityModel.resolve_movement(fighter.health, rules.fighter.max_health, fighter.stamina, stamina_max, rules.combat)
			FacingSystem.step(fighter, targets[slot * 2], targets[slot * 2 + 1], tracking[slot], rules.fighter, turn_cap, _scratch[slot])
			var burst := MovementSystem.step(fighter, state.opponent_of(slot), commands[slot].axis_x(), commands[slot].axis_y(), tick, rules.fighter, move_cap, _scratch[slot])
			if burst != MovementGestureState.BurstKind.NONE:
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
			MovementSystem.coast(fighter, rules.fighter)
	for slot in 2:
		var fighter := state.fighter(slot)
		var weapon_cap := 1.0
		if fighter.is_alive():
			var stamina_max := StaminaModel.max_for_health(fighter.health, rules.fighter.max_health, rules.fighter.base_stamina, rules.combat)
			weapon_cap = CapabilityModel.resolve_weapon(fighter.health, rules.fighter.max_health, fighter.stamina, stamina_max, rules.combat)
		WeaponSystem.step(fighter, state.opponent_of(slot), rules, tick, events, weapon_cap, _scratch[slot])
	## Step 10: arena boundary confinement only. Body separation shares the
	## TOI chronology (COMBAT-007) rather than running before sword contacts,
	## because a separation pass can move a fighter away from a sword tip and
	## erase a stab that chronologically preceded the body overlap.
	ArenaConstraints.confine(a, rules.arena_radius - rules.fighter.body_radius)
	ArenaConstraints.confine(b, rules.arena_radius - rules.fighter.body_radius)
	_finish[0].write(a)
	_finish[1].write(b)
	ContactResolver.update_bind(state, rules, tick, events)
	_resolve_contacts(state, tick, events)
	_stamina_step(state, rules)
	state.blade_contact.tick()
	for wbc in state.weapon_body_contacts:
		if wbc.phase == WeaponBodyContact.Phase.ENTERED:
			wbc.phase = WeaponBodyContact.Phase.INSIDE
	_check_round_end(state, events)


## Apply stamina drain, recovery, and contact shock once per tick. All motors
## have run and all contacts have resolved, so the scratch is complete. Each
## fighter is processed independently — no cross-read (symmetry).
func _stamina_step(state: MatchState, duel_rules: DuelRules) -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	for slot in 2:
		var fighter := state.fighter(slot)
		var tuning := duel_rules.combat
		var stamina_max := StaminaModel.max_for_health(
			fighter.health, duel_rules.fighter.max_health, duel_rules.fighter.base_stamina, tuning
		)
		if not fighter.is_alive():
			fighter.stamina = clampf(fighter.stamina, 0.0, stamina_max)
			continue
		var scratch := _scratch[slot]
		var effort := StaminaModel.total_effort(scratch, tuning)
		var drain := StaminaModel.exertion(effort, dt, tuning)
		var recover := StaminaModel.recovery(effort, fighter.stamina, stamina_max, dt, tuning)
		fighter.stamina = clampf(fighter.stamina - drain + recover - scratch.contact_shock, 0.0, stamina_max)


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
	for _resolved in limit:
		_collision.detect(state, _start, _finish, rules, state.blade_contact, _report)
		if not _report.any():
			return
		var toi := elapsed + (1.0 - elapsed) * _report.fraction
		_seek(state, _report.fraction)
		_start[0].write(state.fighter(0))
		_start[1].write(state.fighter(1))
		ContactResolver.resolve(state, _report, rules, tick, toi, events, _scratch)
		_carry(state, 1.0 - toi)
		_finish[0].write(state.fighter(0))
		_finish[1].write(state.fighter(1))
		elapsed = toi
	## Bounded iteration is not optional on a mobile budget. Saturation means
	## the geometry is pathological, so the pair is held in contact — a
	## tunnelled blade would be far worse than a missed impulse.
	state.blade_contact.set_phase(ContactPairState.Phase.CONTACTING)
	events.append(DuelEvent.create(DuelEventTypes.CONTACT_SATURATED, tick, DuelEvent.NONE, DuelEvent.NONE, {
		DuelEventKeys.COUNT: limit,
	}))


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


## Carry both fighters through the remaining `share` of the tick under their
## post-contact velocities. The motor has already run, so this is the same
## linear integration the systems themselves performed — just over what is
## left of the tick.
func _carry(state: MatchState, share: float) -> void:
	var dt := SimulationTimebase.TICK_SECONDS * share
	var limit := rules.weapon.guard_limit
	for slot in 2:
		var fighter := state.fighter(slot)
		fighter.x += fighter.vx * dt
		fighter.y += fighter.vy * dt
		fighter.facing = SimMath.wrap_angle(fighter.facing + fighter.turn_rate * dt)
		var weapon := fighter.weapon
		weapon.angle = clampf(weapon.angle + weapon.speed * dt, -limit, limit)
	ArenaConstraints.resolve(state.fighter(0), state.fighter(1), rules)


## While the result is shown, bodies brake and blades settle; nothing new can
## happen, so settling events are discarded.
func _step_result(state: MatchState, events: Array[DuelEvent]) -> void:
	state.phase_ticks += 1
	var settling: Array[DuelEvent] = []
	for slot in 2:
		var fighter := state.fighter(slot)
		MovementSystem.coast(fighter, rules.fighter)
		fighter.clear_attack_input()
		WeaponSystem.step(fighter, state.opponent_of(slot), rules, state.tick, settling)
	ArenaConstraints.resolve(state.fighter(0), state.fighter(1), rules)
	if state.phase_ticks < rules.result_ticks:
		return
	var scores := state.scores
	if scores[0] >= rules.rounds_to_win or scores[1] >= rules.rounds_to_win:
		_end_match(state, 0 if scores[0] > scores[1] else 1, MatchPhase.REASON_SCORE, events)
	elif state.round_number >= rules.max_rounds:
		var winner := MatchPhase.DRAW
		if scores[0] != scores[1]:
			winner = 0 if scores[0] > scores[1] else 1
		_end_match(state, winner, MatchPhase.REASON_ROUND_LIMIT, events)
	else:
		state.round_number += 1
		DuelSetup.reset_round(state, rules)
		state.set_phase(MatchPhase.Id.ROUND_INTRO)


func _check_round_end(state: MatchState, events: Array[DuelEvent]) -> void:
	var a_alive := state.fighter(0).is_alive()
	var b_alive := state.fighter(1).is_alive()
	var timed_out := state.round_ticks >= rules.round_time_limit_ticks
	if a_alive and b_alive and not timed_out:
		return
	var winner := MatchPhase.DRAW
	var reason := MatchPhase.REASON_KILL
	if not a_alive and not b_alive:
		winner = _trade_winner(state)
		reason = MatchPhase.REASON_DOUBLE_KILL if winner == MatchPhase.DRAW else MatchPhase.REASON_TRADE_FIRST_CONTACT
	elif not a_alive:
		winner = 1
	elif not b_alive:
		winner = 0
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
	state.set_phase(MatchPhase.Id.ROUND_RESULT)
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
	var a := state.fighter(0).lethal_fraction
	var b := state.fighter(1).lethal_fraction
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
