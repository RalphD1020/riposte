class_name CombatMetrics
extends RefCounted

## Test-only: what a played duel *did*, counted from its events — attacks,
## clashes, parries, body hits by kind, kills, ring-outs, rounds. The
## golden corpus pins these beside its hashes, so a deliberate rules change
## (a new attack path, a contact solver) shows what changed in the fighting
## and not just that a hash moved (SIM-002).
##
## See also: /docs/reference/testing.md

const COUNTED: Array[StringName] = [
	DuelEventTypes.ATTACK_RELEASED,
	DuelEventTypes.BLADE_CONTACT,
	DuelEventTypes.PARRY,
	DuelEventTypes.BODY_HIT,
	DuelEventTypes.BODY_POKE,
	DuelEventTypes.BODY_THRUST,
	DuelEventTypes.CRITICAL_HIT,
	DuelEventTypes.FIGHTER_KILLED,
	DuelEventTypes.RING_OUT,
	DuelEventTypes.ROUND_ENDED,
]


## Event-type → count for `runner`'s duel, in `COUNTED` order.
static func of(runner: SimRunner) -> Dictionary:
	var counts := {}
	for type in COUNTED:
		counts[String(type)] = runner.count(type)
	return counts
