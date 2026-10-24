class_name SkinColorwayProfile
extends Resource

## DEFAULT is the costume's own materials. Product matches do not apply
## ALTERNATE: Main and Alternate are meshes, and side is the accent channel.
## The stored dictionary remains so a test can still name those materials.
## It must not recolor a body or a blade.
##
## DEFAULT is implied by the model's own authored materials, so only the
## ALTERNATE overrides are stored (material resource name → Material), applied
## the same way skins override materials. The weapon follows the fighter
## colorway, so these keys may name body and weapon materials together.
##
## Implements: /spec/invariants.md#pres-kit-001
## See also: /docs/concepts/presentation.md

enum Variant { DEFAULT, ALTERNATE }

@export var colorway_id: StringName = &""
@export var alternate_materials: Dictionary = {}


func has_alternate() -> bool:
	return not alternate_materials.is_empty()


## The overrides for a variant: ALTERNATE's dictionary, or empty for DEFAULT.
func overrides(variant: Variant) -> Dictionary:
	return alternate_materials if variant == Variant.ALTERNATE and has_alternate() else {}


## Apply a variant's overrides to an instanced model, by authored material
## resource name, exactly as a skin does. DEFAULT touches nothing.
func apply(model: Node, variant: Variant) -> void:
	var swaps := overrides(variant)
	if swaps.is_empty() or model == null:
		return
	for node: Node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface in mesh_instance.mesh.get_surface_count():
			var authored := mesh_instance.mesh.surface_get_material(surface)
			if authored != null and swaps.has(authored.resource_name):
				mesh_instance.set_surface_override_material(surface, swaps[authored.resource_name] as Material)
