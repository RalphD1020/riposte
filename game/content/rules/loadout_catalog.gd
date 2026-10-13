class_name LoadoutCatalog
extends RefCounted

## Resolves a combatant — a character with a weapon — into the one immutable
## `CombatantPhysicsSpec` the simulation reads (LOADOUT-001). Character body,
## weapon and the fighter ↔ weapon handling are each authored on their own
## (`FighterCatalog`, `WeaponCatalog`, `HandlingCatalog`); this is the only
## place they meet. Any missing piece — an unknown id, or a pair with no
## authored handling — yields null and the match fails closed. It never falls
## back to the reference duelist, the bastard sword, or another pair's track.
##
## See also: /docs/concepts/content.md


## The character `fighter_id` holding `weapon_id`, or null.
static func compile(fighter_id: StringName, weapon_id: StringName) -> CombatantPhysicsSpec:
	var fighter := FighterCatalog.of(fighter_id)
	if fighter == null:
		return null
	var weapon := WeaponCatalog.of(weapon_id, fighter.grip_radius)
	return assemble(fighter, weapon)


## Compile already-authored definitions (prototypes, synthetic fixtures):
## the pair's handling comes from `HandlingCatalog` or the result is null.
static func assemble(fighter: FighterDefinition, weapon: WeaponDefinition) -> CombatantPhysicsSpec:
	var handling := HandlingCatalog.of(fighter, weapon)
	if handling == null:
		return null
	return CombatantPhysicsSpec.compile(fighter, weapon, handling)


## The character's default weapon. Content decides it, not the simulation.
static func default_weapon(fighter_id: StringName) -> StringName:
	if fighter_id == ContentIds.FIGHTER_DUELIST:
		return ContentIds.WEAPON_BASTARD_SWORD
	return &""
