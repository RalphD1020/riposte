class_name CombatantPhysicsSpec
extends RefCounted

## Everything physical about one combatant, resolved once before tick 0
## (COMBATANT-GENERIC-001, LOADOUT-001). The simulation has no character
## identities: both fighters are a `FighterState` driven through the same
## systems by one of these, and every difference between two fighters —
## movement, reach, weapon geometry, mass, inertia, force, materials and
## handling — is a difference in this data, never a branch.
##
## ```text
## CombatantPhysicsSpec
## ├── fighter   FighterDefinition      body (mass, height, push / hurt
## │                                    geometry, hands) and actuators
## │                                    (forces N, torques N·m, speed caps)
## ├── weapon    WeaponDefinition       the object: geometry, mass
## │                                    distribution, grip stations, contact
## │                                    material, motor torques, damage
## └── handling  WeaponHandlingProfile  this body holding this weapon: the
##                                      hilt track C(θ) and its carriage
## ```
##
## A rule set (`DuelRules.combatants`) holds one per fighter slot. Systems
## receive the match context and read `DuelRules.spec_of(fighter)`, or take a
## spec directly; nothing in the simulation reaches for a catalog, a default
## fighter, or a reference weapon (lint: COMBATANT-GENERIC).
##
## Immutable after compilation, and shared freely: two slots may hold equal
## specs or even the same instance. Runtime state (`FighterState`) never copies
## a value out of here.
##
## Implements: /spec/invariants.md#combatant-generic-001
## Implements: /spec/invariants.md#loadout-001
## See also: /docs/concepts/content.md
## Source: game/content/rules/loadout_catalog.gd

## Bump when the meaning or layout of the resolved content changes, so a
## replay recorded against another content schema is refused, not reinterpreted.
## (4: `FighterDefinition.grip_damage_factor` left the digest. Rules 55.)
## (5: weapon restitution moved into its `ContactMaterial`, and each body
## gained one; both materials are digested.)
const CONTENT_SCHEMA_VERSION := 5

var fighter: FighterDefinition
var weapon: WeaponDefinition
var handling: WeaponHandlingProfile


static func compile(fighter_definition: FighterDefinition, weapon_definition: WeaponDefinition, handling_profile: WeaponHandlingProfile) -> CombatantPhysicsSpec:
	var spec := CombatantPhysicsSpec.new()
	spec.fighter = fighter_definition
	spec.weapon = weapon_definition
	spec.handling = handling_profile
	return spec


func is_valid() -> bool:
	return problem() == ""


## Why this loadout cannot fight, or "" when it can. Invalid content fails
## closed — no duel, never a substituted fighter, weapon or track.
func problem() -> String:
	if fighter == null or weapon == null or handling == null:
		return "the fighter, weapon or handling is missing"
	if not fighter.is_valid():
		return "the fighter definition is invalid"
	if not weapon.is_valid():
		return "the weapon definition is invalid"
	var held := handling.problem(fighter, weapon)
	if held != "":
		return held
	var gap := WeaponKinematics.least_surface_gap(self)
	if gap < 0.0:
		return "the attack track puts a hand or the sword %.3f m inside the hurt torso" % -gap
	return ""


func character_id() -> StringName:
	return fighter.id


func weapon_id() -> StringName:
	return weapon.id


func handling_id() -> StringName:
	return handling.id


## A deterministic SHA-256 of every resolved physical value — fighter, weapon
## (its mass distribution included) and handling (its baked track included) —
## from the exact IEEE-754 bits, in declaration order. A replay header carries
## it so a recording can never run silently against different content under
## the same ids. Static content; never part of the per-tick state hash.
func fingerprint() -> String:
	var ints := PackedInt64Array([CONTENT_SCHEMA_VERSION])
	var floats := PackedFloat64Array()
	var names := PackedStringArray()
	_digest(fighter, ints, floats, names)
	_digest(fighter.material if fighter != null else null, ints, floats, names)
	_digest(weapon, ints, floats, names)
	_digest(weapon.material if weapon != null else null, ints, floats, names)
	_digest(handling, ints, floats, names)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(ints.to_byte_array())
	context.update(floats.to_byte_array())
	context.update("\n".join(names).to_utf8_buffer())
	return context.finish().hex_encode()


static func _digest(source: Object, ints: PackedInt64Array, floats: PackedFloat64Array, names: PackedStringArray) -> void:
	if source == null:
		ints.append(-1)
		return
	for property in source.get_property_list():
		if (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var value: Variant = source.get(property["name"])
		match typeof(value):
			TYPE_FLOAT:
				floats.append(value)
			TYPE_INT, TYPE_BOOL:
				ints.append(int(value))
			TYPE_STRING, TYPE_STRING_NAME:
				names.append(String(value))
			TYPE_PACKED_FLOAT64_ARRAY:
				ints.append((value as PackedFloat64Array).size())
				floats.append_array(value)
			TYPE_PACKED_INT32_ARRAY:
				ints.append((value as PackedInt32Array).size())
				for entry in value as PackedInt32Array:
					ints.append(entry)
			TYPE_ARRAY:
				ints.append((value as Array).size())
				for entry: Variant in value as Array:
					if entry is Object:
						_digest(entry, ints, floats, names)
					else:
						floats.append(float(entry))
			TYPE_OBJECT:
				_digest(value as Object, ints, floats, names)
