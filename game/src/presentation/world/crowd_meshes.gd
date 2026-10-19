class_name CrowdMeshes
extends RefCounted

## Authored crowd parts, or a named box when the glb has not been exported.
## The box is the fallback. It is not a second person built per seat.
##
## See also: /docs/concepts/presentation.md

const SEATED := "res://assets/generated/crowd/seated.glb"
const CHEER := "res://assets/generated/crowd/cheer.glb"
const HAIR_CROP := "res://assets/generated/crowd/hair_crop.glb"
const HAIR_BUN := "res://assets/generated/crowd/hair_bun.glb"
const FACE := "res://assets/generated/crowd/face.glb"
const FALLBACK := "fallback"

static var _cache: Dictionary = {}


static func part(cheer: bool, slot: String) -> Mesh:
	var path := CHEER if cheer else SEATED
	var found := _named(path, slot)
	if found != null:
		return found
	return _fallback("%s.%s" % [FALLBACK, slot])


static func face() -> Mesh:
	var found := _named(FACE, "face")
	if found != null:
		return found
	return _fallback(FALLBACK + ".face")


static func hair(bun: bool) -> Mesh:
	var path := HAIR_BUN if bun else HAIR_CROP
	var found := _named(path, "hair")
	if found != null:
		return found
	return _fallback(FALLBACK + ".hair")


static func pose_scene(cheer: bool) -> PackedScene:
	var path := CHEER if cheer else SEATED
	if ResourceLoader.exists(path):
		return load(path) as PackedScene
	return null


static func _named(path: String, slot: String) -> Mesh:
	var key := "%s:%s" % [path, slot]
	if _cache.has(key):
		return _cache[key] as Mesh
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var root := packed.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while stack.size() > 0:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and String(node.name).to_lower() == slot:
			found = (node as MeshInstance3D).mesh
			break
		for child: Node in node.get_children():
			stack.append(child)
	root.free()
	if found != null:
		_cache[key] = found
	return found


static func _fallback(fallback_name: String) -> Mesh:
	if _cache.has(fallback_name):
		return _cache[fallback_name] as Mesh
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.9, 0.28)
	mesh.resource_name = fallback_name
	_cache[fallback_name] = mesh
	return mesh
