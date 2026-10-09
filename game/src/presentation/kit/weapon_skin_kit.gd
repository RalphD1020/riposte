class_name WeaponSkinKit
extends Resource

## A cosmetic variant of a weapon, layered over the base weapon kit. The
## blade's geometry, grip markers, and every physical quantity are the
## weapon definition's; a skin changes only the look of what the
## simulation-posed `SwordPivot` carries.
##
## Implements: /spec/invariants.md#pres-kit-001
## See also: /docs/concepts/presentation.md

@export var skin_id: StringName = &""
@export var base_kit_id: StringName = &""
## Optional replacement for the weapon kit's display scene.
@export var scene: PackedScene
## Optional trail tint; transparent keeps the combatant's blade colour.
@export var trail_tint: Color = Color(0, 0, 0, 0)
## Material resource name → Material, as for FighterSkinKit.
@export var material_overrides: Dictionary = {}


func applies_to(kit: PresentationKit) -> bool:
	return kit != null and kit.id == base_kit_id


func has_trail_tint() -> bool:
	return trail_tint.a > 0.0


func apply(model: Node) -> void:
	if material_overrides.is_empty():
		return
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var authored := mesh_instance.mesh.surface_get_material(surface)
			if authored != null and material_overrides.has(authored.resource_name):
				mesh_instance.set_surface_override_material(surface, material_overrides[authored.resource_name] as Material)
