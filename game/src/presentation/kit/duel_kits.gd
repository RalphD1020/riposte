class_name DuelKits
extends RefCounted

## The kits one match renders with, resolved once at mount from the rules'
## content ids. Presenters receive this instead of looking anything up.
##
## See also: /docs/concepts/presentation.md

var fighter: PresentationKit
var weapon: PresentationKit
var arena: PresentationKit


static func resolve(catalog: PresentationKitCatalog, rules: DuelRules) -> DuelKits:
	var kits := DuelKits.new()
	kits.fighter = catalog.resolve(rules.fighter.id, PresentationKit.PRIMITIVE_FIGHTER)
	kits.weapon = catalog.resolve(rules.weapon.id, PresentationKit.PRIMITIVE_BLADE)
	kits.arena = catalog.resolve(rules.arena_id, PresentationKit.PRIMITIVE_ARENA)
	return kits


func is_complete() -> bool:
	return fighter != null and weapon != null and arena != null
