class_name MatchState
extends RefCounted

## Complete authoritative duel state. Owned and mutated only by
## DuelSimulation; everything else reads it (or a projection of it).
##
## See also: /docs/concepts/simulation.md

var tick: int = 0
var seed_value: int = 0
var phase: MatchPhase.Id = MatchPhase.Id.ROUND_INTRO
var phase_ticks: int = 0
var round_number: int = 1
var round_ticks: int = 0
var scores: PackedInt32Array = PackedInt32Array([0, 0])
var round_winner: int = MatchPhase.NO_WINNER
var match_winner: int = MatchPhase.NO_WINNER
var end_reason: StringName = &""
var fighters: Array[FighterState] = []
## Lifecycle of the blade-on-blade pair. MVP-0 has exactly one pair; adding a
## shield or a second weapon adds instances here, not new booleans.
var blade_contact := ContactPairState.new()
## Lifecycle of weapon→body contacts, one per attacker (COMBAT-007, PHYS-008).
## weapon_body_contacts[i] tracks whether attacker i's blade is currently
## inside the opponent's body volume.
var weapon_body_contacts: Array[WeaponBodyContact] = [WeaponBodyContact.new(), WeaponBodyContact.new()]
## Lifecycle of the body-body pair (PHYS-009). Distinguishes a new-contact
## impact (restitution) from persistent contact (nonpenetration constraint).
var body_contact := BodyContactState.new()


func fighter(slot: int) -> FighterState:
	return fighters[slot]


func opponent_of(slot: int) -> FighterState:
	return fighters[1 - slot]


func is_finished() -> bool:
	return phase == MatchPhase.Id.MATCH_ENDED


func set_phase(next: MatchPhase.Id) -> void:
	phase = next
	phase_ticks = 0
