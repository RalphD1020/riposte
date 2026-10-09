class_name FighterSkinKit
extends Resource

## A cosmetic variant of a fighter body, layered over the base fighter kit.
## Same skeleton, clips, and `FighterDefinition`; only what is drawn changes.
## Every field is optional: an empty skin is the base look.
##
## Applied once at build, never per frame. A skin can never reach gameplay:
## the proxy receives it after the rules are fixed and the hash never sees it.
##
## Implements: /spec/invariants.md#pres-kit-001
## See also: /docs/concepts/presentation.md

@export var skin_id: StringName = &""
## The fighter kit id this skin dresses. A skin for another body is refused.
@export var base_kit_id: StringName = &""
## Optional full scene replacement (same rig contract as the base scene).
@export var scene: PackedScene
## Node name → Mesh to swap in, or `null` to hide that node.
@export var mesh_overrides: Dictionary = {}
## Material resource name (as authored in Blender) → Material.
@export var material_overrides: Dictionary = {}
## DEFAULT/ALTERNATE material sets for a Wolf-vs-Wolf mirror; overrides the
## base kit's colorway when this skin is worn.
@export var colorway: SkinColorwayProfile


func applies_to(kit: PresentationKit) -> bool:
	return kit != null and kit.id == base_kit_id


## Dress an instanced model. Unknown node or material names are ignored, so a
## skin authored against a richer rig degrades rather than breaks.
func apply(model: Node) -> void:
	for node_name: Variant in mesh_overrides:
		var target := model.find_child(str(node_name), true, false) as MeshInstance3D
		if target == null:
			continue
		var replacement := mesh_overrides[node_name] as Mesh
		if replacement == null:
			target.visible = false
		else:
			target.mesh = replacement
	if material_overrides.is_empty():
		return
	for mesh_instance: Node in model.find_children("*", "MeshInstance3D", true, false):
		_apply_materials(mesh_instance as MeshInstance3D)


func _apply_materials(mesh_instance: MeshInstance3D) -> void:
	if mesh_instance.mesh == null:
		return
	for surface in mesh_instance.mesh.get_surface_count():
		var authored := mesh_instance.mesh.surface_get_material(surface)
		if authored != null and material_overrides.has(authored.resource_name):
			mesh_instance.set_surface_override_material(surface, material_overrides[authored.resource_name] as Material)
