class_name FacePresentation
extends RefCounted

## Alive eyes, the brow bar, and the dead-face X marks are all in the art
## file. This only shows the set that matches the fighter's terminal state:
## living eyes while alive, the X in place of those eyes when dead. The brow
## stays visible in both states. A kill and a ring-out both show the X while
## that body is still on screen. A new proxy starts alive, which is how a
## rematch gets the living face back.
##
## `bind` walks once, at proxy build. Later poses call `apply_bound` and skip
## the write while the terminal state is unchanged.
##
## See also: /docs/concepts/presentation.md


static func apply(root: Node, alive: bool) -> void:
	if root == null:
		return
	apply_bound(bind(root), alive)


static func bind(root: Node) -> Array[Node3D]:
	var parts: Array[Node3D] = []
	_collect(root, parts)
	return parts


static func apply_bound(parts: Array[Node3D], alive: bool) -> void:
	for node in parts:
		var part := String(node.name)
		if part.begins_with("DeadEye"):
			node.visible = not alive
		elif part.begins_with("Brow"):
			node.visible = true
		else:
			node.visible = alive


static func _collect(node: Node, parts: Array[Node3D]) -> void:
	if node is Node3D:
		var part := String(node.name)
		if part.begins_with("DeadEye") or part.begins_with("Eye") or part.begins_with("Brow"):
			parts.append(node as Node3D)
	for child in node.get_children():
		_collect(child, parts)
