class_name CrowdStage
extends Node3D

## The bowl's spectators. `CrowdDirector` still names the cue. This stage
## only decides how many existing seats move, how far that spreads, and how
## long they hold. Rematch resets poses. Quitting frees this node with the
## scaffold.
##
## See also: /docs/concepts/presentation.md

const SECTIONS := 8
const SEATS := 8
const ROW := 4
const INNER_RADIUS := 11.2
const OUTER_RADIUS := 12.4
const SEAT_HEIGHT := 0.35
const SETTLE_SECONDS := 0.2
const MOVE_EPSILON := 0.04

const COVERAGE_SMALL := 2
const COVERAGE_PARRY := 3
const COVERAGE_HEAVY := 5
const COVERAGE_STEEL := 4
const COVERAGE_FINISH := 6
const COVERAGE_VICTORY := 8
const HOLD_SHORT := 0.35
const HOLD_STEEL := 0.45
const HOLD_HEAVY := 0.9
const HOLD_FINISH := 1.3
const HOLD_VICTORY := 1.6
const RECOVERY := 0.8
## How far the meter must rise before a silent steel tick moves seats.
const EXCITEMENT_RISE := 0.02
const BOX_HEIGHT := 1.1
const BOX_SOUTH := 13.2
const FIGURE_GAP := 0.7
const SECTION_HALF := 1.6

const SKIN: Array[Color] = [
	Color(0.988, 0.914, 0.855), Color(0.973, 0.863, 0.776),
	Color(0.953, 0.804, 0.69), Color(0.925, 0.729, 0.592),
	Color(0.878, 0.647, 0.494), Color(0.808, 0.541, 0.384),
	Color(0.71, 0.439, 0.29), Color(0.553, 0.333, 0.141),
	Color(0.435, 0.271, 0.094), Color(0.29, 0.173, 0.086),
]
const CLOTH: Array[Color] = [
	Color("a85a45"), Color("c4924a"), Color("e6d7c3"), Color("8a9a78"), Color("7f92a8"),
]
const HAIR: Array[Color] = [
	Color("2a2420"), Color("6b4226"), Color("c2a36a"), Color("b7b1a8"),
]

var seed_value: int = 1
var focus_section: int = 0

var _sections: Array[CrowdSection] = []
var _rows: Array[CrowdRoster] = []
var _disc_radius: float = 8.27
var _camera_at := Vector3.INF
var _still := 0.0
var _excitement := 0.0
var _corners := PackedVector3Array()


static func create(p_seed: int, disc_radius: float) -> CrowdStage:
	var stage := CrowdStage.new()
	stage.name = "Crowd"
	stage.seed_value = p_seed if p_seed != 0 else 1
	stage._disc_radius = disc_radius
	stage._corners.resize(8)
	stage._build()
	return stage


func roster_at(index: int) -> CrowdRoster:
	return _rows[index]


func section_count() -> int:
	return _sections.size()


func batch_count() -> int:
	var total := 0
	for section: CrowdSection in _sections:
		total += section.batch_count()
	return total


func instance_count() -> int:
	var total := 0
	for section: CrowdSection in _sections:
		total += section.instance_count()
	return total


func cheering_count() -> int:
	var total := 0
	for section: CrowdSection in _sections:
		total += section.cheering_count()
	return total


func section_hidden(index: int) -> bool:
	return _sections[index].spectators_hidden


func react(cue: StringName, excitement: float) -> void:
	var rose := excitement > _excitement + EXCITEMENT_RISE
	_excitement = excitement
	if cue == CrowdDirector.CUE_GASP or cue == CrowdDirector.CUE_MURMUR:
		return
	if cue == &"":
		if rose and excitement >= CrowdDirector.STRONG_LEVEL:
			_spread(1, COVERAGE_STEEL, HOLD_STEEL, false)
		return
	if cue == CrowdDirector.CUE_VICTORY:
		_spread(3, COVERAGE_VICTORY, HOLD_VICTORY, true)
	elif cue == CrowdDirector.CUE_STRONG:
		_spread(2, COVERAGE_FINISH, HOLD_FINISH, true)
	elif cue == CrowdDirector.CUE_CHEER and excitement >= CrowdDirector.STEP_CRITICAL:
		_spread(1, COVERAGE_HEAVY, HOLD_HEAVY, false)
	elif cue == CrowdDirector.CUE_CHEER:
		_spread(0, COVERAGE_PARRY, HOLD_SHORT, false)
	elif cue == CrowdDirector.CUE_SETPOINT:
		_spread(0, COVERAGE_SMALL, HOLD_SHORT, false)


func advance(delta: float, camera: Camera3D, _reduced_motion: bool) -> void:
	for section: CrowdSection in _sections:
		section.advance(delta)
	if camera == null:
		return
	var origin := camera.global_position
	if _camera_at != Vector3.INF and origin.distance_to(_camera_at) > MOVE_EPSILON:
		_still = 0.0
		_camera_at = origin
		return
	_camera_at = origin
	_still += delta
	if _still < SETTLE_SECONDS:
		return
	_still = 0.0
	_focus_from(camera)
	_apply_visibility(camera)


func reset_poses() -> void:
	for section: CrowdSection in _sections:
		section.reset_poses()


func _focus_from(camera: Camera3D) -> void:
	var forward := -camera.global_transform.basis.z
	var turns := atan2(forward.z, forward.x) / TAU
	focus_section = wrapi(int(round(turns * float(SECTIONS))), 0, SECTIONS)


func _spread(reach: int, coverage: int, hold: float, punch: bool) -> void:
	for offset: int in reach * 2 + 1:
		var index := wrapi(focus_section + offset - reach, 0, SECTIONS)
		var section := _sections[index]
		if section.cooldown > 0.0 and not punch:
			continue
		section.cheer_span(coverage, hold)
		section.cooldown = RECOVERY


func _apply_visibility(camera: Camera3D) -> void:
	var combat := CrowdForeground.project(camera, CrowdForeground.disc_points(_disc_radius))
	for index: int in _sections.size():
		var section := _sections[index]
		var aabb := _section_bounds(index)
		for corner: int in 8:
			_corners[corner] = _corner(aabb, corner)
		var points := CrowdForeground.project(camera, _corners)
		var conceal := CrowdForeground.overlaps(points, combat, section.spectators_hidden)
		if conceal != section.spectators_hidden:
			section.set_spectators_hidden(conceal)


func _build() -> void:
	var seated_skin := CrowdMeshes.part(false, "skin")
	var cheer_skin := CrowdMeshes.part(true, "skin")
	var seated_cloth := CrowdMeshes.part(false, "fabric")
	var cheer_cloth := CrowdMeshes.part(true, "fabric")
	var crop := CrowdMeshes.hair(false)
	var bun := CrowdMeshes.hair(true)
	var previous: CrowdRoster = null
	for index: int in SECTIONS:
		var section := CrowdSection.new()
		section.name = "Section%d" % index
		var seats: Array[Transform3D] = []
		var skin := PackedColorArray()
		var cloth := PackedColorArray()
		var hair := PackedColorArray()
		var crop_used := PackedByteArray()
		var bun_used := PackedByteArray()
		crop_used.resize(SEATS)
		bun_used.resize(SEATS)
		for seat: int in SEATS:
			var global := index * SEATS + seat
			var row := CrowdRoster.assign(seed_value, global, previous)
			previous = row
			_rows.append(row)
			var radius := INNER_RADIUS if seat < ROW else OUTER_RADIUS
			var along := (float(seat % ROW) - 1.5) * 0.55
			var center := TAU * float(index) / float(SECTIONS)
			var angle := center + along / radius
			var at := Vector3(cos(angle) * radius, SEAT_HEIGHT + (0.28 if seat >= ROW else 0.0), sin(angle) * radius)
			var xf := Transform3D.IDENTITY
			xf.origin = at
			xf = xf.looking_at(Vector3(0.0, at.y, 0.0), Vector3.UP)
			seats.append(xf)
			skin.append(SKIN[row.skin])
			cloth.append(CLOTH[row.cloth])
			hair.append(HAIR[row.hair_color])
			if row.hair == 0:
				crop_used[seat] = 1
			else:
				bun_used[seat] = 1
		var everyone := PackedByteArray()
		everyone.resize(SEATS)
		everyone.fill(1)
		section.add_layer(seated_skin, cheer_skin, seats, skin, everyone)
		section.add_layer(seated_cloth, cheer_cloth, seats, cloth, everyone)
		section.add_layer(crop, crop, seats, hair, crop_used)
		section.add_layer(bun, bun, seats, hair, bun_used)
		_sections.append(section)
		add_child(section)
	_build_box()


func _build_box() -> void:
	var box := Node3D.new()
	box.name = "ImperialBox"
	box.position = Vector3(0.0, BOX_HEIGHT, BOX_SOUTH)
	var names: PackedStringArray = ["Emperor", "Attendant", "Dignitary"]
	var shades: Array[Color] = [RiposteTheme.STONE_BRONZE, RiposteTheme.STONE_LIMESTONE, RiposteTheme.STONE_TERRACOTTA]
	var posed := CrowdMeshes.pose_scene(false)
	for index: int in 3:
		var person := MeshInstance3D.new()
		person.name = names[index]
		person.position = Vector3(float(index - 1) * FIGURE_GAP, 0.0, 0.0)
		person.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := StandardMaterial3D.new()
		material.albedo_color = shades[index]
		material.roughness = 0.7
		if posed != null:
			var figure := posed.instantiate()
			figure.name = "Figure"
			person.add_child(figure)
			_tint_rendered(figure, material)
		else:
			person.mesh = CrowdMeshes.part(false, "skin")
			person.material_override = material
		box.add_child(person)
	add_child(box)


func _tint_rendered(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child: Node in node.get_children():
		_tint_rendered(child, material)


func _section_bounds(index: int) -> AABB:
	var center := TAU * float(index) / float(SECTIONS)
	var radius := (INNER_RADIUS + OUTER_RADIUS) * 0.5
	var at := Vector3(cos(center) * radius, 1.0, sin(center) * radius)
	return AABB(at - Vector3(SECTION_HALF, 0.2, SECTION_HALF), Vector3(SECTION_HALF * 2.0, 2.2, SECTION_HALF * 2.0))


func _corner(aabb: AABB, index: int) -> Vector3:
	var spot := aabb.position
	if index & 1:
		spot.x += aabb.size.x
	if index & 2:
		spot.y += aabb.size.y
	if index & 4:
		spot.z += aabb.size.z
	return spot
