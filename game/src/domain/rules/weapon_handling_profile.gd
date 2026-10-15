class_name WeaponHandlingProfile
extends RefCounted

## How one body holds and moves one weapon (LOADOUT-001): the fighter ↔ weapon
## pairing, owned by neither. The hilt track `C(θ)` is how *these* arms carry
## *this* grip — Wolf with a rapier, or a heavier body with the same bastard
## sword, would each need their own — so it lives here, not on the fighter
## (which knows nothing of any weapon) and not on the weapon (which knows
## nothing of any wielder).
##
## A match resolves one handling per combatant into its
## `CombatantPhysicsSpec` before tick 0. A fighter/weapon pair with no
## authored handling fails closed at match creation; it never borrows another
## pair's track.
##
## Immutable after creation. Units: metres, radians.
##
## Implements: /spec/invariants.md#loadout-001
## See also: /docs/concepts/combat.md
## Source: game/content/rules/handling_catalog.gd

var id: StringName = &""
## The pairing this profile was authored for. `CombatantPhysicsSpec` refuses a
## handling resolved against any other fighter or weapon.
var fighter_id: StringName = &""
var weapon_id: StringName = &""
## Where the carriage (grip centre) rides in the combat frame for every θ, and
## its slope (WEAPON-PATH-001/003). Defaults to the fixed, body-centred pivot.
var attack_path: WeaponAttackPath = WeaponAttackPath.fixed_pivot()
## Distance (m) from the weapon's origin (pommel) down the blade to the
## carriage — the point on the sword the track places. A reference point of
## the orbit, not where the hands are (the hands are the weapon's grip
## stations, `WeaponDefinition.offhand_grip_radius` / `dominant_grip_radius`).
var carriage_radius: float = 0.0


## Why this handling cannot carry `weapon` in `fighter`'s hands, or "" when it
## can. Clearance against the wielder's own torso is the spec's check
## (`CombatantPhysicsSpec.problem`), because it needs the whole loadout posed.
func problem(fighter: FighterDefinition, weapon: WeaponDefinition) -> String:
	if fighter == null or weapon == null:
		return "the handling has no fighter or weapon to hold"
	if fighter_id != fighter.id or weapon_id != weapon.id:
		return "the handling %s was authored for %s with %s, not %s with %s" % [id, fighter_id, weapon_id, fighter.id, weapon.id]
	if attack_path == null:
		return "the handling has no attack track"
	if not (carriage_radius >= 0.0 and carriage_radius < weapon.blade_base_radius):
		return "the carriage is not on the weapon's handle"
	## The weapon's origin is its pommel at the wielder's grip, so its handle
	## length must be the distance this fighter's hands hold any weapon.
	if weapon.blade_base_radius != fighter.grip_radius:
		return "the weapon's blade base is not at the fighter's grip"
	return ""
