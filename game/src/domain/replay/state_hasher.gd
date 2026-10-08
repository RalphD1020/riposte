class_name StateHasher
extends RefCounted

## Canonical SHA-256 of every authoritative field, in a fixed order, from the
## exact IEEE-754 bits. If two runs of the same commands disagree on a hash,
## determinism is broken (COMBAT §77). Presentation values never enter here.
##
## Implements: /spec/invariants.md#sim-002
## See also: /docs/concepts/simulation.md


static func hash_state(state: MatchState) -> String:
	var ints := PackedInt64Array([
		state.tick,
		state.seed_value,
		state.phase,
		state.phase_ticks,
		state.round_number,
		state.round_ticks,
		state.scores[0],
		state.scores[1],
		state.round_winner,
		state.match_winner,
		state.blade_contact.phase,
		state.blade_contact.phase_ticks,
		state.body_contact.phase,
		state.body_contact.ticks_in_contact,
	])
	var floats := PackedFloat64Array([
		state.body_contact.last_constraint_impulse,
		state.body_contact.last_constraint_normal_x,
		state.body_contact.last_constraint_normal_y,
	])
	for fighter in state.fighters:
		var weapon := fighter.weapon
		floats.append_array(PackedFloat64Array([
			fighter.x,
			fighter.y,
			fighter.vx,
			fighter.vy,
			fighter.ax,
			fighter.ay,
			fighter.facing,
			fighter.turn_rate,
			fighter.health,
			fighter.stability,
			fighter.stamina,
			fighter.lethal_fraction,
			fighter.duel_forward_x,
			fighter.duel_forward_y,
			fighter.gesture.burst_dir_x,
			fighter.gesture.burst_dir_y,
			weapon.angle,
			weapon.speed,
			weapon.charge,
			weapon.hold_start_angle,
			weapon.earned_windback,
			weapon.stable_side,
			weapon.swing_dir,
			weapon.launch_readiness,
			weapon.swing_start,
			weapon.swing_end,
			weapon.swing_charge,
			weapon.commitment,
			weapon.recovery_commitment,
		]))
		var gesture := fighter.gesture
		ints.append_array(PackedInt64Array([
			fighter.side,
			fighter.stagger_left,
			gesture.sector,
			gesture.sector_ticks,
			gesture.last_direction,
			gesture.first_tap_tick,
			int(gesture.awaiting_second_tap),
			int(gesture.returned_to_neutral),
			gesture.mode,
			gesture.burst_kind,
			gesture.burst_ticks_remaining,
			gesture.recovery_ticks_remaining,
			gesture.recovery_ticks_total,
			int(fighter.attack_held),
			fighter.press_tick,
			fighter.buffered_press_tick,
			int(fighter.buffered_release),
			int(fighter.is_falling),
			weapon.phase,
			weapon.phase_ticks,
			int(weapon.swing_hit),
			int(weapon.swing_contact),
			weapon.recovery_ticks,
			weapon.recovery_left,
			weapon.bind_left,
		]))
	var reason := String(state.end_reason).to_utf8_buffer()
	ints.append(reason.size())
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(ints.to_byte_array())
	context.update(floats.to_byte_array())
	if not reason.is_empty():
		context.update(reason)
	return context.finish().hex_encode()
