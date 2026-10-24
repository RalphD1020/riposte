class_name CrowdMeshes
extends RefCounted

## The crowd's mesh lookup: one named mesh out of an exported figure scene,
## cached, or a named box when the file is missing. The box is a release
## fallback, not a look: `CrowdProfile.problem` and PRES-ARENA fail on a
## missing file. Which files a crowd uses is its `CrowdProfile`.
##
## See also: /docs/concepts/presentation.md

const FALLBACK := "fallback"

static var _cache: Dictionary = {}


static func named(path: String, slot: String) -> Mesh:
	var key := "%s:%s" % [path, slot]
	if _cache.has(key):
		return _cache[key] as Mesh
	var found := _find(path, slot)
	if found == null:
		found = _fallback("%s.%s.%s" % [FALLBACK, path.get_file().get_basename(), slot])
	_cache[key] = found
	return found


static func _find(path: String, slot: String) -> Mesh:
	if path.is_empty() or not ResourceLoader.exists(path):
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
	return found


static func _fallback(fallback_name: String) -> Mesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.34, 0.9, 0.28)
	mesh.resource_name = fallback_name
	return mesh
