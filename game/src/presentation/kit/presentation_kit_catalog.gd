class_name PresentationKitCatalog
extends RefCounted

## Content id → PresentationKit. Development builds fail closed on a missing
## kit (null) so gaps are caught; release builds degrade to a placeholder so
## a missing asset never makes the game unplayable.
##
## See also: /docs/concepts/presentation.md

var fail_closed: bool = true
var _kits: Dictionary = {}
var _fighter_skins: Dictionary = {}
var _weapon_skins: Dictionary = {}


func register(kit: PresentationKit) -> void:
	if kit != null and kit.id != &"":
		_kits[kit.id] = kit


func register_fighter_skin(skin: FighterSkinKit) -> void:
	if skin != null and skin.skin_id != &"":
		_fighter_skins[skin.skin_id] = skin


func register_weapon_skin(skin: WeaponSkinKit) -> void:
	if skin != null and skin.skin_id != &"":
		_weapon_skins[skin.skin_id] = skin


## Unknown or empty skin ids are the base look, in every build: a missing
## cosmetic is never a reason to refuse a match.
func fighter_skin(skin_id: StringName) -> FighterSkinKit:
	return _fighter_skins.get(skin_id) as FighterSkinKit


func weapon_skin(skin_id: StringName) -> WeaponSkinKit:
	return _weapon_skins.get(skin_id) as WeaponSkinKit


func has(kit_id: StringName) -> bool:
	return _kits.has(kit_id)


func resolve(kit_id: StringName, primitive_kind: StringName) -> PresentationKit:
	if _kits.has(kit_id):
		return _kits[kit_id]
	return null if fail_closed else PresentationKit.missing(primitive_kind)


## Ids from `required` that have no kit.
func missing_ids(required: Array[StringName]) -> PackedStringArray:
	var missing := PackedStringArray()
	for kit_id in required:
		if not _kits.has(kit_id):
			missing.append(String(kit_id))
	return missing
