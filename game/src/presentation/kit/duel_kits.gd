class_name DuelKits
extends RefCounted

## The kits one match renders with, resolved once at mount from the rules'
## content ids and an optional per-slot skin choice. Presenters receive this
## instead of looking anything up.
##
## Skins are chosen *after* the rules are fixed and are never read by the
## simulation, so two viewers may dress the same duel differently.
##
## See also: /docs/concepts/presentation.md

var fighter: PresentationKit
var weapon: PresentationKit
var arena: PresentationKit
var combatants: Array[CombatantPresentationKit] = []
var match_loadout: MatchPresentationLoadout


## `fighter_skins` / `weapon_skins`: skin id per slot (missing = base look).
static func resolve(
	catalog: PresentationKitCatalog,
	rules: DuelRules,
	fighter_skins: Array[StringName] = [],
	weapon_skins: Array[StringName] = [],
	loadout: MatchPresentationLoadout = null,
	palette_slot: PackedInt32Array = PackedInt32Array()
) -> DuelKits:
	var kits := DuelKits.new()
	## Each slot is dressed from its own combatant's content ids.
	var fighter_kits: Array[PresentationKit] = []
	var weapon_kits: Array[PresentationKit] = []
	for slot in 2:
		fighter_kits.append(catalog.resolve(rules.combatant(slot).character_id(), PresentationKit.PRIMITIVE_FIGHTER))
		weapon_kits.append(catalog.resolve(rules.combatant(slot).weapon_id(), PresentationKit.PRIMITIVE_BLADE))
	## The match-wide kits (trail sampling, shared cue banks) are slot 0's;
	## per-slot dressing reads `combatant(slot)`.
	kits.fighter = fighter_kits[0]
	kits.weapon = weapon_kits[0]
	kits.arena = catalog.resolve(rules.arena_id, PresentationKit.PRIMITIVE_ARENA)
	## A true visual mirror is the same fighter identity and the same selected
	## skin on both slots; only then does the Dark side take its alternate
	## colorway (COLORWAY). The weapon skin rides the fighter skin's choice.
	var fighter_ids: Array = [rules.combatant(0).character_id(), rules.combatant(1).character_id()]
	var slot_skins: Array = [
		fighter_skins[0] if fighter_skins.size() > 0 else &"",
		fighter_skins[1] if fighter_skins.size() > 1 else &"",
	]
	var mirror := ColorwayResolver.is_mirror(fighter_ids, slot_skins)
	for slot in 2:
		var skin := catalog.fighter_skin(fighter_skins[slot]) if slot < fighter_skins.size() else null
		var blade := catalog.weapon_skin(weapon_skins[slot]) if slot < weapon_skins.size() else null
		var entry := CombatantPresentationKit.of(fighter_kits[slot], weapon_kits[slot], skin, blade)
		entry.mirror = mirror
		if slot < palette_slot.size():
			entry.palette_override = palette_slot[slot]
		kits.combatants.append(entry)
	kits.match_loadout = loadout if loadout != null else MatchPresentationLoadout.of(kits.arena, null, null, null)
	return kits


func is_complete() -> bool:
	return fighter != null and weapon != null and arena != null


func combatant(slot: int) -> CombatantPresentationKit:
	return combatants[slot]
