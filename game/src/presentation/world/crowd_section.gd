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
var _home: Array[Transform3D] = []
var _offset := PackedFloat32Array()
var _arms := PackedByteArray()
var _phase: float = 0.0
var _energy: float = 0.0
var _stand: float = 0.0
var _stand_target: float = 0.0
## A hidden seat keeps its place and drops out of the draw. Not a second allocation.
const HIDDEN_SCALE := 0.001
## The arms-up mesh is the cheer. Lifting the whole block hovered it off the
## tread in the Compatibility captures, so the stand stays on the seat.
const STAND_LIFT := 0.0
const STAND_RATE := 1.0 / 0.45
const PHASE_STEP := 0.73


func add_layer(seated_mesh: Mesh, cheer_mesh: Mesh, seats: Array[Transform3D], colors: PackedColorArray, used: PackedByteArray) -> void:
	if _seat_count == 0:
		_seat_count = seats.size()
		_cheering.resize(_seat_count)
		_hold.resize(_seat_count)
		_offset.resize(_seat_count)
		_arms.resize(_seat_count)
		for index: int in seats.size():
			_home.append(seats[index])
			_offset[index] = float(index) * PHASE_STEP
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
	if _stand >= 0.5:
		return _seat_count
	return 0


func stand_weight() -> float:
	return _stand


func stand_target() -> float:
	return _stand_target


func set_energy(energy: float) -> void:
	_energy = clampf(energy, 0.0, 1.0)


func set_stand_target(target: float) -> void:
	_stand_target = target


func phase_of(index: int) -> float:
	if index < 0 or index >= _offset.size():
		return _phase
	return _phase + _offset[index]


func prime_phase(bias: float) -> void:
	_phase = bias


## Kept so a caller can ask a span to rise. Standing is section-wide now.
func cheer_span(count: int, hold: float) -> int:
	if count <= 0:
		return 0
	set_stand_target(1.0)
	for index: int in mini(count, _seat_count):
		_hold[index] = maxf(_hold[index], hold)
	return mini(count, _seat_count)


func arms_up_count() -> int:
	var total := 0
	for flag: int in _arms:
		total += flag
	return total


func advance(delta: float, sway: bool = true) -> void:
	if cooldown > 0.0:
		cooldown = maxf(cooldown - delta, 0.0)
	if sway:
		var rate := lerpf(2.4, 4.2, _energy)
		_phase += delta * rate
	_stand = move_toward(_stand, _stand_target, STAND_RATE * maxf(delta, 0.0))
	_pose_all(sway)
	for index: int in _seat_count:
		if _hold[index] <= 0.0:
			continue
		_hold[index] = maxf(_hold[index] - delta, 0.0)


func reset_poses() -> void:
	cooldown = 0.0
	_stand = 0.0
	_stand_target = 0.0
	_energy = 0.0
	for index: int in _seat_count:
		_cheering[index] = 0
		_hold[index] = 0.0
	_pose_all(true)


func set_spectators_hidden(hidden: bool) -> void:
	spectators_hidden = hidden
	visible = not hidden


func _pose_all(sway: bool) -> void:
	if _home.is_empty() or _seated.is_empty():
		return
	var amp := lerpf(0.08, 0.16, _energy) if sway else 0.0
	## Quiet seats still throw their arms. A louder room keeps more of them up.
	## The wave is per seat, so the row does not rise as one block. The origin
	## stays on the tread; a vertical bob lifted them off the stone.
	var gate := lerpf(0.42, -0.2, _energy)
	for index: int in _seat_count:
		var home := _home[index]
		var wave := sin(_phase + _offset[index])
		var lean := wave * amp * (1.0 - _stand)
		var posed := home
		posed.origin.y += STAND_LIFT * _stand
		posed.basis = home.basis.rotated(home.basis.x.normalized(), lean)
		var hidden := Transform3D(Basis.from_scale(Vector3(HIDDEN_SCALE, HIDDEN_SCALE, HIDDEN_SCALE)), posed.origin)
		var standing := _stand >= 0.35
		var cheering := standing or (sway and wave > gate)
		_arms[index] = 1 if cheering else 0
		for layer: int in _seated.size():
			if _used[layer][index] == 0:
				continue
			_seated[layer].multimesh.set_instance_transform(index, hidden if cheering else posed)
			_cheer[layer].multimesh.set_instance_transform(index, posed if cheering else hidden)


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
