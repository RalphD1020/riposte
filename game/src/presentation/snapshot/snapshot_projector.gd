class_name SnapshotProjector
extends RefCounted

## The single boundary where presentation reads authoritative state: copies a
## MatchState into an immutable PresentationSnapshot once per tick.
##
## See also: /docs/concepts/presentation.md


static func project(state: MatchState, rules: DuelRules) -> PresentationSnapshot:
	var snapshot := PresentationSnapshot.new()
	snapshot.tick = state.tick
	snapshot.phase = state.phase
	snapshot.phase_ticks = state.phase_ticks
	snapshot.round_number = state.round_number
	snapshot.rounds_to_win = rules.rounds_to_win
	snapshot.scores = state.scores.duplicate()
	snapshot.round_winner = state.round_winner
	snapshot.match_winner = state.match_winner
	snapshot.end_reason = state.end_reason
	snapshot.intro_ticks = rules.intro_ticks
	snapshot.time_left_ticks = maxi(rules.round_time_limit_ticks - state.round_ticks, 0)
	var a := state.fighter(0)
	var b := state.fighter(1)
	snapshot.distance = DuelGeometry.distance(a, b)
	snapshot.closing_speed = DuelGeometry.closing_speed(a, b)
	snapshot.orbit_rate = DuelGeometry.orbit_rate(a, b)
	for slot in 2:
		snapshot.fighters.append(_fighter(state.fighter(slot), state.opponent_of(slot), rules))
	return snapshot


static func _fighter(fighter: FighterState, opponent: FighterState, rules: DuelRules) -> PresentationFighter:
	var row := PresentationFighter.new()
	var weapon := fighter.weapon
	row.slot = fighter.slot
	row.x = fighter.x
	row.y = fighter.y
	row.facing = fighter.facing
	row.blade_angle = DuelGeometry.blade_angle(fighter)
	row.weapon_angle = weapon.angle
	row.blade_speed = absf(fighter.turn_rate + weapon.speed)
	row.charge = weapon.charge
	row.phase = weapon.phase
	row.commitment = weapon.commitment
	row.stability = fighter.stability
	row.health = fighter.health
	row.max_health = rules.fighter.max_health
	row.body_radius = rules.fighter.body_radius
	row.hilt_radius = rules.weapon.hilt_radius
	row.tip_radius = rules.weapon.tip_radius
	row.threat_time = InitiativeModel.time_to_threat(fighter, opponent, rules)
	return row
