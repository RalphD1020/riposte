class_name DuelRules
extends RefCounted

## Complete, immutable rule set for one duel — the match's physics context:
## one resolved `CombatantPhysicsSpec` per fighter slot, the combat tuning,
## the arena and the match format. Same rules + seed + commands → same result.
## Every value is authored in content; defaults here are neutral.
##
## The two combatants are independent (COMBATANT-GENERIC-001). Nothing here is
## "the" fighter or "the" weapon: a mirror match simply holds two equal specs,
## and a system that needs a fighter's physics asks `spec_of(fighter)`.
##
## Implements: /spec/invariants.md#sim-001
## Implements: /spec/invariants.md#combatant-generic-001
## See also: /docs/concepts/simulation.md
## Source: game/content/rules/standard_duel_rules.gd

## Replays pin rules by id + version; bump the version when any value changes.
var id: StringName = &""
var version: int = 0

## Indexed by fighter slot (`FighterState.slot`); exactly two.
var combatants: Array[CombatantPhysicsSpec] = []
var combat: CombatTuning
## How the surfaces in this duel meet (CONTACT-MATERIAL-001). Each weapon and
## body brings its own `ContactMaterial`; the table resolves the pairs.
var materials: ContactMaterialTable = ContactMaterialTable.new()
## The stage's collidable structures (STRUCTURE-CONTACT-001), in a fixed order
## that is their identity in contact records. Empty on an open disc.
var structures: Array[StageObjectDef] = []

## Arena. `EDGE_OPEN` rings out at `platform_radius` (version 58). `EDGE_CLOSED`
## holds the centre inside the support radius and does not emit `RING_OUT`.
const EDGE_OPEN := &"open"
const EDGE_CLOSED := &"closed"
## Most structures one rule set may carry (fixed record capacity).
const MAX_STRUCTURES := 16
var arena_id: StringName = &""
var platform_radius: float = 0.0
var edge_warning_inset: float = 0.0
var edge_policy: StringName = EDGE_OPEN
var spawn_offset: float = 0.0

## Match format. rounds_to_win = 3 is best of five.
var rounds_to_win: int = 0
var max_rounds: int = 0
var intro_ticks: int = 0
var result_ticks: int = 0
var round_time_limit_ticks: int = 0
## How long the winner controls the stage after a round ends (POST_ROUND_FREE).
var post_round_free_ticks: int = 0


## The physics of the fighter in `slot`.
func combatant(slot: int) -> CombatantPhysicsSpec:
	return combatants[slot]


## The physics of `fighter` — the one lookup every system uses.
func spec_of(fighter: FighterState) -> CombatantPhysicsSpec:
	return combatants[fighter.slot]


## Resolved material pairs, rebuilt only when the table or a combatant's
## material changes. Reading one is a comparison, never a lookup by id.
var _pairs_revision: int = -1
var _blade_pair: ContactPair
var _sword_body_pairs: Array[ContactPair] = [null, null]
var _body_pair: ContactPair
## Per fighter slot, per structure (same order as `structures`).
var _structure_pairs: Array = [[], []]


## A deterministic SHA-256 of the world the swords meet: the material table
## and every structure (id, material, shapes), from the exact IEEE-754 bits in
## authored order. A replay header carries it, so a recording is refused
## against other walls or other grips under the same rules version. Static
## content; never part of the per-tick state hash.
func world_fingerprint() -> String:
	var ints := PackedInt64Array()
	var floats := PackedFloat64Array()
	var names := PackedStringArray()
	materials.digest(ints, floats, names)
	ints.append(structures.size())
	for structure: StageObjectDef in structures:
		names.append(String(structure.object_id))
		ints.append_array(PackedInt64Array([int(structure.blocks_blade), structure.motion, structure.shapes.size()]))
		names.append(String(structure.material.id))
		floats.append_array(PackedFloat64Array([structure.material.restitution, structure.material.restitution_threshold_speed, structure.material.friction]))
		for shape: StructureShape in structure.shapes:
			ints.append(shape.kind)
			floats.append_array(PackedFloat64Array([shape.cx, shape.cy, shape.radius, shape.from_x, shape.from_y, shape.to_x, shape.to_y, shape.ax, shape.ay, shape.bx, shape.by, shape.half_thickness]))
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(ints.to_byte_array())
	context.update(floats.to_byte_array())
	context.update("\n".join(names).to_utf8_buffer())
	return context.finish().hex_encode()


## Fighter `slot`'s sword on structure `index`.
func structure_pair(slot: int, index: int) -> ContactPair:
	_refresh_pairs()
	return _structure_pairs[slot][index]


## Sword 0's steel on sword 1's.
func blade_pair() -> ContactPair:
	_refresh_pairs()
	return _blade_pair


## Fighter `attacker`'s sword on the other fighter's body.
func sword_body_pair(attacker: int) -> ContactPair:
	_refresh_pairs()
	return _sword_body_pairs[attacker]


## The two bodies.
func body_pair() -> ContactPair:
	_refresh_pairs()
	return _body_pair


func _refresh_pairs() -> void:
	var weapon_0 := combatants[0].weapon.material
	var weapon_1 := combatants[1].weapon.material
	var body_0 := combatants[0].fighter.material
	var body_1 := combatants[1].fighter.material
	if _pairs_revision == materials.revision and _blade_pair != null and _blade_pair.a == weapon_0 and _blade_pair.b == weapon_1 and _body_pair.a == body_0 and _body_pair.b == body_1 and (_structure_pairs[0] as Array).size() == structures.size():
		return
	_blade_pair = materials.resolve(weapon_0, weapon_1)
	_sword_body_pairs[0] = materials.resolve(weapon_0, body_1)
	_sword_body_pairs[1] = materials.resolve(weapon_1, body_0)
	_body_pair = materials.resolve(body_0, body_1)
	var weapons: Array[ContactMaterial] = [weapon_0, weapon_1]
	for slot in 2:
		var row: Array[ContactPair] = []
		for structure: StageObjectDef in structures:
			row.append(materials.resolve(weapons[slot], structure.material))
		_structure_pairs[slot] = row
	_pairs_revision = materials.revision


func is_valid() -> bool:
	return problem() == ""


## Why these rules cannot run a duel, or "" when they can. Invalid rules fail
## closed — no duel, never a substituted rule set or loadout (WEAPON-PATH-003,
## LOADOUT-001) — and this is the diagnostic that says which part is wrong.
func problem() -> String:
	if combatants.size() != 2 or combat == null:
		return "the two combatants or the combat tuning are missing"
	for slot in 2:
		if combatants[slot] == null:
			return "combatant %d is missing" % slot
		var loadout := combatants[slot].problem()
		if loadout != "":
			return "combatant %d: %s" % [slot, loadout]
	if not combat.is_valid():
		return "the combat tuning is invalid"
	if materials == null or materials.problem() != "":
		return "the material table: %s" % ("missing" if materials == null else materials.problem())
	if edge_policy != EDGE_OPEN and edge_policy != EDGE_CLOSED:
		return "the edge policy is unknown"
	if structures.size() > MAX_STRUCTURES:
		return "more structures than the contact records hold"
	for structure: StageObjectDef in structures:
		if structure == null:
			return "a structure is missing"
		var broken := structure.problem()
		if broken != "":
			return broken
	if rounds_to_win <= 0 or max_rounds < rounds_to_win * 2 - 1 or round_time_limit_ticks <= 0 or post_round_free_ticks < 0:
		return "the match format is invalid"
	for slot in 2:
		var push := combatants[slot].fighter.push_radius
		if platform_radius <= spawn_offset + push or spawn_offset <= push:
			return "the arena cannot hold the fighters apart"
		if combat.guard_limit_zone >= combatants[slot].weapon.guard_limit:
			return "combatant %d: the soft-limit zone is as wide as the guard" % slot
	return ""


## Visual warning ring radius, derived from the physical platform edge.
func warning_ring_radius() -> float:
	return platform_radius - edge_warning_inset


## True when a centre that reaches the support radius is held, not rung out.
func is_closed_edge() -> bool:
	return edge_policy == EDGE_CLOSED
