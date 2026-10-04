class_name ReplayVerifier
extends RefCounted

## Re-simulates a ReplayRecord through a fresh DuelSimulation and compares the
## final state hash. A mismatch means determinism is broken or the record was
## altered (COMBAT §77). The same check is the future server-authority gate.
##
## Implements: /spec/invariants.md#sim-002
## See also: /docs/concepts/simulation.md

const VERIFIED := &"verified"
const RULES_MISMATCH := &"rules_mismatch"
const INVALID_RULES := &"invalid_rules"
const HASH_MISMATCH := &"hash_mismatch"


static func verify(record: ReplayRecord, rules: DuelRules) -> StringName:
	if not record.matches_rules(rules):
		return RULES_MISMATCH
	var simulation := DuelSimulation.create(rules)
	if simulation == null:
		return INVALID_RULES
	var state := replay(record, simulation)
	return VERIFIED if StateHasher.hash_state(state) == record.final_hash else HASH_MISMATCH


static func replay(record: ReplayRecord, simulation: DuelSimulation) -> MatchState:
	var state := simulation.new_match(record.seed_value)
	for index in record.tick_count():
		simulation.step(state, record.command_at(0, index), record.command_at(1, index))
	return state
