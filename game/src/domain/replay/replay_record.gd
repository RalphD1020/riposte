class_name ReplayRecord
extends RefCounted

## Everything needed to reproduce a duel (COMBAT §77, PLAN Phase 11.2):
## rules identity, both combatants' loadouts, seed, and the tick-indexed
## commands of both fighters. Commands are packed integers so the record
## serializes exactly.
##
## The header pins the immutable context the commands were recorded against
## (LOADOUT-001): per slot, the character, weapon and handling ids plus a
## fingerprint of the resolved physical content, and the content schema
## version, the state-hash layout, and the world the swords meet (the material
## table and the stage's structures, `DuelRules.world_fingerprint`). A
## recording therefore never runs silently against different
## content under the same ids — old Wolf against a retuned Wolf is refused, not
## reinterpreted. The per-tick state hash stays dynamic state only.
##
## See also: /docs/concepts/simulation.md

## 3: the world fingerprint.
const FORMAT_VERSION := 3
const KEY_FORMAT := "format"
const KEY_RULES_ID := "rules_id"
const KEY_RULES_VERSION := "rules_version"
const KEY_CONTENT_SCHEMA := "content_schema_version"
const KEY_STATE_LAYOUT := "state_layout_version"
const KEY_COMBATANTS := "combatants"
const KEY_FIGHTER_ID := "fighter_id"
const KEY_WEAPON_ID := "weapon_id"
const KEY_HANDLING_ID := "handling_id"
const KEY_FINGERPRINT := "fingerprint"
const KEY_SEED := "seed"
const KEY_COMMANDS_0 := "commands_0"
const KEY_COMMANDS_1 := "commands_1"
const KEY_FINAL_HASH := "final_hash"
const KEY_WORLD := "world"

var rules_id: StringName = &""
var rules_version: int = 0
var content_schema_version: int = 0
var state_layout_version: int = 0
## Per slot: [fighter id, weapon id, handling id, content fingerprint].
var combatants: Array[PackedStringArray] = []
## Materials and structures (STRUCTURE-CONTACT-001).
var world_fingerprint: String = ""
var seed_value: int = 0
var commands_0: PackedInt32Array = PackedInt32Array()
var commands_1: PackedInt32Array = PackedInt32Array()
var final_hash: String = ""


static func begin(rules: DuelRules, match_seed: int) -> ReplayRecord:
	var record := ReplayRecord.new()
	record.rules_id = rules.id
	record.rules_version = rules.version
	record.content_schema_version = CombatantPhysicsSpec.CONTENT_SCHEMA_VERSION
	record.state_layout_version = StateHasher.LAYOUT_VERSION
	record.combatants = loadouts_of(rules)
	record.world_fingerprint = rules.world_fingerprint()
	record.seed_value = match_seed
	return record


## The loadout header `rules` would record.
static func loadouts_of(rules: DuelRules) -> Array[PackedStringArray]:
	var out: Array[PackedStringArray] = []
	for spec in rules.combatants:
		out.append(PackedStringArray([String(spec.character_id()), String(spec.weapon_id()), String(spec.handling_id()), spec.fingerprint()]))
	return out


func append(command_0: PlayerCommand, command_1: PlayerCommand) -> void:
	command_0.append_to(commands_0)
	command_1.append_to(commands_1)


func tick_count() -> int:
	return floori(float(commands_0.size()) / float(PlayerCommand.PACKED_STRIDE))


func command_at(slot: int, index: int) -> PlayerCommand:
	return PlayerCommand.read_from(commands_0 if slot == 0 else commands_1, index)


## Whether `rules` are the exact context this record was made against: the
## same rules id and version, the same content schema and state-hash layout,
## and per slot the same
## loadout ids and resolved-content fingerprint.
func matches_rules(rules: DuelRules) -> bool:
	if rules == null or rules.id != rules_id or rules.version != rules_version:
		return false
	if content_schema_version != CombatantPhysicsSpec.CONTENT_SCHEMA_VERSION or state_layout_version != StateHasher.LAYOUT_VERSION:
		return false
	return loadouts_of(rules) == combatants and rules.world_fingerprint() == world_fingerprint


func to_dictionary() -> Dictionary:
	var loadouts: Array = []
	for entry in combatants:
		loadouts.append({
			KEY_FIGHTER_ID: entry[0],
			KEY_WEAPON_ID: entry[1],
			KEY_HANDLING_ID: entry[2],
			KEY_FINGERPRINT: entry[3],
		})
	return {
		KEY_FORMAT: FORMAT_VERSION,
		KEY_RULES_ID: String(rules_id),
		KEY_RULES_VERSION: rules_version,
		KEY_CONTENT_SCHEMA: content_schema_version,
		KEY_STATE_LAYOUT: state_layout_version,
		KEY_COMBATANTS: loadouts,
		KEY_WORLD: world_fingerprint,
		KEY_SEED: seed_value,
		KEY_COMMANDS_0: Array(commands_0),
		KEY_COMMANDS_1: Array(commands_1),
		KEY_FINAL_HASH: final_hash,
	}


## Returns null for an unknown format, malformed command streams or a
## malformed loadout header.
static func from_dictionary(data: Dictionary) -> ReplayRecord:
	if int(data.get(KEY_FORMAT, -1)) != FORMAT_VERSION:
		return null
	var first := PackedInt32Array(data.get(KEY_COMMANDS_0, []))
	var second := PackedInt32Array(data.get(KEY_COMMANDS_1, []))
	if first.size() != second.size() or first.size() % PlayerCommand.PACKED_STRIDE != 0:
		return null
	var loadouts: Variant = data.get(KEY_COMBATANTS, [])
	if not (loadouts is Array) or (loadouts as Array).size() != 2:
		return null
	var record := ReplayRecord.new()
	for entry: Variant in loadouts as Array:
		if not (entry is Dictionary):
			return null
		var row := entry as Dictionary
		record.combatants.append(PackedStringArray([
			str(row.get(KEY_FIGHTER_ID, "")),
			str(row.get(KEY_WEAPON_ID, "")),
			str(row.get(KEY_HANDLING_ID, "")),
			str(row.get(KEY_FINGERPRINT, "")),
		]))
	record.rules_id = StringName(str(data.get(KEY_RULES_ID, "")))
	record.rules_version = int(data.get(KEY_RULES_VERSION, 0))
	record.content_schema_version = int(data.get(KEY_CONTENT_SCHEMA, 0))
	record.state_layout_version = int(data.get(KEY_STATE_LAYOUT, 0))
	record.world_fingerprint = str(data.get(KEY_WORLD, ""))
	record.seed_value = int(data.get(KEY_SEED, 0))
	record.commands_0 = first
	record.commands_1 = second
	record.final_hash = str(data.get(KEY_FINAL_HASH, ""))
	return record
