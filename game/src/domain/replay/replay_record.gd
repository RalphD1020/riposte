class_name ReplayRecord
extends RefCounted

## Everything needed to reproduce a duel (COMBAT §77, PLAN Phase 11.2):
## rules identity, seed, and the tick-indexed commands of both fighters.
## Commands are packed integers so the record serializes exactly.
##
## See also: /docs/concepts/simulation.md

const FORMAT_VERSION := 1
const KEY_FORMAT := "format"
const KEY_RULES_ID := "rules_id"
const KEY_RULES_VERSION := "rules_version"
const KEY_SEED := "seed"
const KEY_COMMANDS_0 := "commands_0"
const KEY_COMMANDS_1 := "commands_1"
const KEY_FINAL_HASH := "final_hash"

var rules_id: StringName = &""
var rules_version: int = 0
var seed_value: int = 0
var commands_0: PackedInt32Array = PackedInt32Array()
var commands_1: PackedInt32Array = PackedInt32Array()
var final_hash: String = ""


static func begin(rules: DuelRules, match_seed: int) -> ReplayRecord:
	var record := ReplayRecord.new()
	record.rules_id = rules.id
	record.rules_version = rules.version
	record.seed_value = match_seed
	return record


func append(command_0: PlayerCommand, command_1: PlayerCommand) -> void:
	command_0.append_to(commands_0)
	command_1.append_to(commands_1)


func tick_count() -> int:
	return floori(float(commands_0.size()) / float(PlayerCommand.PACKED_STRIDE))


func command_at(slot: int, index: int) -> PlayerCommand:
	return PlayerCommand.read_from(commands_0 if slot == 0 else commands_1, index)


func matches_rules(rules: DuelRules) -> bool:
	return rules != null and rules.id == rules_id and rules.version == rules_version


func to_dictionary() -> Dictionary:
	return {
		KEY_FORMAT: FORMAT_VERSION,
		KEY_RULES_ID: String(rules_id),
		KEY_RULES_VERSION: rules_version,
		KEY_SEED: seed_value,
		KEY_COMMANDS_0: Array(commands_0),
		KEY_COMMANDS_1: Array(commands_1),
		KEY_FINAL_HASH: final_hash,
	}


## Returns null for an unknown format or malformed command streams.
static func from_dictionary(data: Dictionary) -> ReplayRecord:
	if int(data.get(KEY_FORMAT, -1)) != FORMAT_VERSION:
		return null
	var first := PackedInt32Array(data.get(KEY_COMMANDS_0, []))
	var second := PackedInt32Array(data.get(KEY_COMMANDS_1, []))
	if first.size() != second.size() or first.size() % PlayerCommand.PACKED_STRIDE != 0:
		return null
	var record := ReplayRecord.new()
	record.rules_id = StringName(str(data.get(KEY_RULES_ID, "")))
	record.rules_version = int(data.get(KEY_RULES_VERSION, 0))
	record.seed_value = int(data.get(KEY_SEED, 0))
	record.commands_0 = first
	record.commands_1 = second
	record.final_hash = str(data.get(KEY_FINAL_HASH, ""))
	return record
