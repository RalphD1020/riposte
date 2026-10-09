class_name CombatantPresentationKit
extends RefCounted

## Everything one combatant is drawn and heard with: the base fighter and
## weapon kits plus optional cosmetic overlays. The split exists because the
## same fighter may hold different weapons and different fighters may hold
## the same weapon; overlays exist so a skin is a kit edit, never a rig or
## rules edit. `null` overlays mean "the base kit's look".
##
## Implements: /spec/invariants.md#pres-kit-001
## See also: /docs/concepts/presentation.md

var fighter: PresentationKit
var weapon: PresentationKit
var fighter_skin: FighterSkinKit
var weapon_skin: WeaponSkinKit
## True only in a true visual mirror (same fighter + same skin on both slots),
## which is the only time the Dark/North copy uses its ALTERNATE colorway.
var mirror: bool = false


static func of(fighter_kit: PresentationKit, weapon_kit: PresentationKit, skin: FighterSkinKit = null, blade_skin: WeaponSkinKit = null) -> CombatantPresentationKit:
	var combatant := CombatantPresentationKit.new()
	combatant.fighter = fighter_kit
	combatant.weapon = weapon_kit
	combatant.fighter_skin = skin if skin != null and skin.applies_to(fighter_kit) else null
	combatant.weapon_skin = blade_skin if blade_skin != null and blade_skin.applies_to(weapon_kit) else null
	return combatant


func voice() -> FighterVoiceKit:
	return fighter.voice if fighter != null else null


func intro() -> FighterIntroProfile:
	return fighter.intro if fighter != null else null


## The body scene to instance: a skin's full replacement wins over the base.
func body_scene() -> PackedScene:
	if fighter_skin != null and fighter_skin.scene != null:
		return fighter_skin.scene
	return fighter.scene


func weapon_scene() -> PackedScene:
	if weapon_skin != null and weapon_skin.scene != null:
		return weapon_skin.scene
	return weapon.scene


## The colorway in force: a worn skin's colorway wins over the base kit's.
func colorway() -> SkinColorwayProfile:
	if fighter_skin != null and fighter_skin.colorway != null:
		return fighter_skin.colorway
	return fighter.colorway if fighter != null else null


## The material overrides to paint for a fighter on `side`. DEFAULT (every
## ordinary matchup, and the Light side of a mirror) is empty. The weapon
## follows the fighter, so these may name body and weapon materials together.
func colorway_overrides(side: DuelSide.Id) -> Dictionary:
	var profile := colorway()
	if profile == null:
		return {}
	return profile.overrides(ColorwayResolver.variant_for(side, mirror))
