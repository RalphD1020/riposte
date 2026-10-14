class_name StateHasher
extends RefCounted

## Canonical SHA-256 of every authoritative field, in a fixed order, from the
## exact IEEE-754 bits. If two runs of the same commands disagree on a hash,
## determinism is broken (COMBAT §77). Presentation values never enter here.
##
## Implements: /spec/invariants.md#sim-002
## See also: /docs/concepts/simulation.md

## Which fields the hash covers, in which order. A schema change that is not a
## rules change (2: the stamina pool left state, STAMINA-003) moves every hash
## without changing the game, so recordings name it and are refused across it.
## (3: a swing's HAND episode, `WeaponState.hand_struck`, DEFENSE-ROLE-001.)
## (4: a swing's pending deflection, `WeaponState.deflection_pending`,
## DEFLECTION-001.)
const LAYOUT_VERSION := 4


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
	## Warm-start impulses are carried into the next tick's solve, so they are
	## state (RIGID-CONTACT-003).
	var manifold := state.blade_contact
	## So is contact identity (CONTACT-IDENTITY-001): which hold record a row
	## matches reads its feature coordinates, and a point's id and age carry.
	## The hold record is compact, so its length and its entries are all of it.
	var held := manifold.hold_count()
	ints.append_array(PackedInt64Array([manifold.point_count, manifold.next_contact_id, held]))
	for i in held:
		ints.append_array(PackedInt64Array([manifold.hold_active[i], manifold.hold_feature_a[i], manifold.hold_feature_b[i]]))
		floats.append_array(PackedFloat64Array([manifold.hold_normal[i], manifold.hold_tangent[i], manifold.hold_local_a[i], manifold.hold_local_b[i]]))
	for i in manifold.point_count:
		ints.append_array(PackedInt64Array([manifold.contact_id[i], manifold.age[i]]))
	for lifecycle in state.weapon_body_contacts:
		ints.append(int(lifecycle.hold_active))
		floats.append_array(PackedFloat64Array([lifecycle.hold_normal, lifecycle.hold_tangent]))
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
			fighter.lethal_fraction,
			fighter.support_lost_fraction,
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
			weapon.launch_preparation,
			weapon.swing_start,
			weapon.swing_end,
			weapon.swing_charge,
			weapon.commitment,
			weapon.motor_torque,
			weapon.recovery_commitment,
			fighter.fallen.yaw,
			fighter.fallen.spin,
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
			int(weapon.attack_contacted),
			int(weapon.hand_struck),
			int(weapon.deflection_pending),
			weapon.recovery_ticks,
			weapon.recovery_left,
			int(fighter.fallen.active),
			fighter.fallen.settle_left,
			int(fighter.fallen.over_edge),
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
