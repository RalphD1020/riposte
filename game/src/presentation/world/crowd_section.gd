class_name CrowdSection
extends Node3D

## One stretch of stands. Seated and cheer batches are allocated together.
## A reaction moves existing instances between them. It does not allocate.
##
## See also: /docs/concepts/presentation.md

var cooldown: float = 0.0
var spectators_hidden: bool = false

var _seated: Array[MultiMeshInstance3D] = []
var _cheer: Array[MultiMeshInstance3D] = []
var _used: Array[PackedByteArray] = []
var _cheering: PackedByteArray = PackedByteArray()
var _hold: PackedFloat32Array = PackedFloat32Array()
var _seat_count: int = 0
## A hidden seat keeps its place and drops out of the draw. Not a second allocation.
const HIDDEN_SCALE := 0.001


func add_layer(seated_mesh: Mesh, cheer_mesh: Mesh, seats: Array[Transform3D], colors: PackedColorArray, used: PackedByteArray) -> void:
	if _seat_count == 0:
		_seat_count = seats.size()
		_cheering.resize(_seat_count)
		_hold.resize(_seat_count)
	_used.append(used)
	_seated.append(_batch("Seated%d" % _seated.size(), seated_mesh, seats, colors, used, true))
	_cheer.append(_batch("Cheer%d" % _cheer.size(), cheer_mesh, seats, colors, used, false))


func batch_count() -> int:
	return _seated.size() + _cheer.size()


func instance_count() -> int:
	var total := 0
	for layer: MultiMeshInstance3D in _seated:
		total += layer.multimesh.instance_count
	for layer: MultiMeshInstance3D in _cheer:
		total += layer.multimesh.instance_count
	return total


func cheering_count() -> int:
	var total := 0
	for index: int in _seat_count:
		total += int(_cheering[index])
	return total


## The first `count` seats that are not already cheering stand up.
func cheer_span(count: int, hold: float) -> int:
	var raised := 0
	var limit := mini(count, _seat_count)
	for index: int in limit:
		if _cheering[index] == 1:
			_hold[index] = maxf(_hold[index], hold)
			continue
		_apply_pose(index, true, hold)
		raised += 1
	return raised


func advance(delta: float) -> void:
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
	for index: int in _seat_count:
		if _hold[index] <= 0.0:
			continue
		_hold[index] = maxf(_hold[index] - delta, 0.0)
		if _hold[index] <= 0.0:
			_apply_pose(index, false, 0.0)


func reset_poses() -> void:
	cooldown = 0.0
	for index: int in _seat_count:
		_apply_pose(index, false, 0.0)


func set_spectators_hidden(hidden: bool) -> void:
	spectators_hidden = hidden
	visible = not hidden


func _apply_pose(index: int, cheering: bool, hold: float) -> void:
	_cheering[index] = 1 if cheering else 0
	_hold[index] = hold
	var seat := _seat_transform(index)
	var hidden := Transform3D(Basis.from_scale(Vector3(HIDDEN_SCALE, HIDDEN_SCALE, HIDDEN_SCALE)), seat.origin)
	for layer: int in _seated.size():
		if _used[layer][index] == 0:
			continue
		_seated[layer].multimesh.set_instance_transform(index, hidden if cheering else seat)
		_cheer[layer].multimesh.set_instance_transform(index, seat if cheering else hidden)


func _seat_transform(index: int) -> Transform3D:
	var seated_xf := _seated[0].multimesh.get_instance_transform(index)
	if seated_xf.basis.get_scale().x > HIDDEN_SCALE * 10.0:
		return seated_xf
	return _cheer[0].multimesh.get_instance_transform(index)


func _batch(batch_name: String, mesh: Mesh, seats: Array[Transform3D], colors: PackedColorArray, used: PackedByteArray, seated: bool) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.use_colors = true
	multi.mesh = mesh
	multi.instance_count = seats.size()
	var node := MultiMeshInstance3D.new()
	node.name = batch_name
	node.multimesh = multi
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.material_override = _tinted(mesh)
	for index: int in seats.size():
		var seat := seats[index]
		var hidden := Transform3D(Basis.from_scale(Vector3(HIDDEN_SCALE, HIDDEN_SCALE, HIDDEN_SCALE)), seat.origin)
		var draw := used[index] == 1 and seated
		multi.set_instance_transform(index, seat if draw else hidden)
		multi.set_instance_color(index, colors[index] if index < colors.size() else Color.WHITE)
	add_child(node)
	return node


func _tinted(mesh: Mesh) -> Material:
	var source := mesh.surface_get_material(0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.WHITE
	material.roughness = 0.85
	if source is StandardMaterial3D:
		material.roughness = (source as StandardMaterial3D).roughness
	material.vertex_color_use_as_albedo = true
	return material
