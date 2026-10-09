class_name SkinColorwayProfile
extends Resource

## Two material sets for one look: DEFAULT (the character's own palette) and
## ALTERNATE. This is a **mirror-match discriminator, not a team identity** —
## in an ordinary matchup every character wears its default regardless of
## side; only in a true visual mirror (same fighter identity AND the same
## selected skin on both slots) does the Dark/North copy switch to ALTERNATE
## so the two are told apart. Side readability still comes from the separate
## SideAccent channel, applied afterward, so this is redundant on top of it.
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
