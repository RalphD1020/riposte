class_name CombatantVisuals
extends RefCounted

## The one recipe for a combatant's look, built fresh from its kits: the body
## scene with its skin, the side's colorway, and the side accent on the kit's
## colour targets; the weapon scene with its skin and the same colorway. The
## match proxy, a dropped sword, and a showcase actor all build from here, so
## none of them clones a live subtree (scripts, trails, emitters) and a mirror
## colorway can never be applied in one place and forgotten in another.
##
## See also: /docs/concepts/presentation.md

## The primitive blade's thickness when no weapon scene is authored (m).
const PRIMITIVE_BLADE_THICKNESS := 0.035


## The authored body for `side`, or null when the kit is primitive. Colorway
## goes on before the side accent, so the accent channel always wins and side
## stays legible even in a mirror.
static func body_model(combatant: CombatantPresentationKit, side: DuelSide.Id) -> Node3D:
	var scene := combatant.body_scene()
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	if combatant.fighter_skin != null:
		combatant.fighter_skin.apply(model)
	apply_colorway(combatant, side, model)
	for target in combatant.fighter.color_targets:
		var mesh := model.find_child(target, true, false) as MeshInstance3D
		if mesh != null:
			mesh.material_override = material(RiposteTheme.accent_for(side))
	return model


## The authored weapon for `side`, or null when the kit is primitive. Laid out
## along local +Z from the pivot, like the sword pivot it is mounted under.
static func weapon_model(combatant: CombatantPresentationKit, side: DuelSide.Id) -> Node3D:
	var scene := combatant.weapon_scene()
	if scene == null:
		return null
	var model := scene.instantiate() as Node3D
	model.name = "WeaponModel"
	if combatant.weapon_skin != null:
		combatant.weapon_skin.apply(model)
	apply_colorway(combatant, side, model)
	return model


## A weapon look for a prop (a dropped sword): the authored weapon when there
## is one, else a primitive blade box between `hilt` and `tip`.
static func weapon_look(combatant: CombatantPresentationKit, side: DuelSide.Id, hilt: float, tip: float) -> Node3D:
	var look := Node3D.new()
	look.name = "WeaponLook"
	var model := weapon_model(combatant, side)
	if model != null:
		look.add_child(model)
		return look
	var blade := MeshInstance3D.new()
	blade.name = "Blade"
	var box := BoxMesh.new()
	box.size = Vector3(combatant.weapon.blade_width, PRIMITIVE_BLADE_THICKNESS, maxf(tip - hilt, PRIMITIVE_BLADE_THICKNESS))
	blade.mesh = box
	blade.material_override = material(RiposteTheme.blade_for(side))
	blade.position.z = hilt + (tip - hilt) * 0.5
	look.add_child(blade)
	return look


## The combatant's colorway override for this side (empty for DEFAULT), by
## authored material name, on either the body or the weapon model.
static func apply_colorway(combatant: CombatantPresentationKit, side: DuelSide.Id, model: Node) -> void:
	var profile := combatant.colorway()
	if profile == null:
		return
	profile.apply(model, combatant.chosen_variant(side))


static func material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	if unshaded:
		result.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return result
