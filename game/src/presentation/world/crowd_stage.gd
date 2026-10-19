class_name CrowdStage
extends Node3D

## The bowl's spectators. Seats come from `ArenaSection`. During a match they
## stay in their seats: they rock, and a shifting share swap to the arms-up
## mesh. A louder room keeps more arms up. A name chant stands the sections
## on that fighter's side of the bowl. The match result stands everyone. A
## round roar does not. Reduced motion drops the seated wave and still lets a
## stand finish. Rematch builds a new stage.
##
## See also: /docs/concepts/presentation.md

const SETTLE_SECONDS := 0.2
const MOVE_EPSILON := 0.04
const FIGURE_GAP := 0.7
## Sections within this ring distance of the named fighter's side stand.
const CHANT_SPAN := 1
## Stable offset so neighboring sections do not lean on the same beat.
const SECTION_PHASE := 1.3

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
## Wolf's eyes and brow are the dark hair slot, not the dyed hair.
const FACE_INK := Color(0.03, 0.03, 0.035)

var seed_value: int = 1
var focus_section: int = 0

var _sections: Array[CrowdSection] = []
var _rows: Array[CrowdRoster] = []
var _disc_radius: float = 8.27
var _layout: ArenaSection
var _bounds: Array[AABB] = []
var _origins := PackedVector3Array()
var _camera_at := Vector3.INF
var _still := 0.0
var _excitement := 0.0
var _chant := false
var _match_celebration := false
var _corners := PackedVector3Array()


static func create(p_seed: int, disc_radius: float) -> CrowdStage:
	var stage := CrowdStage.new()
	stage.name = "Crowd"
	stage.seed_value = p_seed if p_seed != 0 else 1
	stage._disc_radius = disc_radius
	stage._corners.resize(8)
	stage._build()
	return stage


func layout() -> ArenaSection:
	return _layout


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


func placed_origins() -> PackedVector3Array:
	return _origins


func cheering_count() -> int:
	var total := 0
	for section: CrowdSection in _sections:
		total += section.cheering_count()
	return total


func section_hidden(index: int) -> bool:
	return _sections[index].spectators_hidden


func seated_energy() -> float:
	return _excitement


func phase_of(index: int) -> float:
	return phase_of_section(0, index)


func phase_of_section(section_index: int, seat: int = 0) -> float:
	if section_index < 0 or section_index >= _sections.size():
		return 0.0
	return _sections[section_index].phase_of(seat)


func arms_up_count() -> int:
	var total := 0
	for section: CrowdSection in _sections:
		total += section.arms_up_count()
	return total


func standing_sections() -> int:
	var total := 0
	for section: CrowdSection in _sections:
		if section.stand_target() >= 0.5:
			total += 1
	return total


func react(cue: StringName, excitement: float) -> void:
	_excitement = clampf(excitement, 0.0, 1.0)
	for section: CrowdSection in _sections:
		section.set_energy(_excitement)
	if cue == CrowdDirector.CUE_VICTORY:
		_match_celebration = true
		_chant = false
	_apply_stand_targets()


func hold_chant(active: bool) -> void:
	if _match_celebration:
		return
	_chant = active
	_apply_stand_targets()


## The sections behind this fighter, not the sections the camera faces.
func focus_on_side(side: DuelSide.Id) -> void:
	if _layout == null:
		return
	var at := ArenaTransform.to_world(0.0, DuelSide.home_sign(side), 0.0)
	focus_section = _layout.section_for(atan2(at.z, at.x))


func advance(delta: float, camera: Camera3D, reduced_motion: bool) -> void:
	for section: CrowdSection in _sections:
		section.set_energy(_excitement)
		section.advance(delta, not reduced_motion)
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
	_chant = false
	_match_celebration = false
	_excitement = 0.0
	for section: CrowdSection in _sections:
		section.reset_poses()


func _apply_stand_targets() -> void:
	var count := _sections.size()
	for index: int in count:
		var want := false
		if _match_celebration:
			want = true
		elif _chant:
			var gap := absi(index - focus_section)
			gap = mini(gap, count - gap)
			want = gap <= CHANT_SPAN
		_sections[index].set_stand_target(1.0 if want else 0.0)


func _focus_from(camera: Camera3D) -> void:
	if _chant:
		return
	var count := _sections.size()
	if count == 0:
		return
	var forward := -camera.global_transform.basis.z
	var turns := atan2(forward.z, forward.x) / TAU
	focus_section = wrapi(int(round(turns * float(count))), 0, count)


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
	_layout = ArenaSection.load_layout()
	if not _layout.issues().is_empty():
		return
	var seated_skin := CrowdMeshes.part(false, "skin")
	var cheer_skin := CrowdMeshes.part(true, "skin")
	var seated_cloth := CrowdMeshes.part(false, "fabric")
	var cheer_cloth := CrowdMeshes.part(true, "fabric")
	var crop := CrowdMeshes.hair(false)
	var bun := CrowdMeshes.hair(true)
	var face := CrowdMeshes.face()
	var count := _layout.section_count
	var seat_section := PackedInt32Array()
	var poses: Array[Transform3D] = []
	_bounds.resize(count)
	var started: Array[bool] = []
	started.resize(count)
	var previous: CrowdRoster = null
	var global := 0
	for tier: int in _layout.tier_count():
		for bay: int in _layout.bay_count:
			for slot: int in _layout.slots_in_bay(tier):
				var pose := _layout.pose_for(tier, bay, slot)
				var row := CrowdRoster.assign(seed_value, global, previous)
				previous = row
				_rows.append(row)
				poses.append(pose)
				_origins.append(pose.origin)
				var section_index := _layout.section_for(atan2(pose.origin.z, pose.origin.x))
				seat_section.append(section_index)
				_include(section_index, pose.origin, started)
				global += 1
	for index: int in count:
		if not started[index]:
			_bounds[index] = AABB(Vector3(0.0, -20.0, 0.0), Vector3.ONE)
			continue
		var box := _bounds[index].grow(0.45)
		box.size.y += 1.2
		_bounds[index] = box
	for index: int in count:
		var section := CrowdSection.new()
		section.name = "Section%d" % index
		section.prime_phase(float(index) * SECTION_PHASE)
		var seats: Array[Transform3D] = []
		var skin := PackedColorArray()
		var cloth := PackedColorArray()
		var hair := PackedColorArray()
		var which: PackedInt32Array = []
		for seat: int in poses.size():
			if seat_section[seat] != index:
				continue
			seats.append(poses[seat])
			which.append(seat)
			skin.append(SKIN[_rows[seat].skin])
			cloth.append(CLOTH[_rows[seat].cloth])
			hair.append(HAIR[_rows[seat].hair_color])
		if seats.is_empty():
			_sections.append(section)
			add_child(section)
			continue
		var crop_used := PackedByteArray()
		var bun_used := PackedByteArray()
		crop_used.resize(seats.size())
		bun_used.resize(seats.size())
		for local: int in which.size():
			if _rows[which[local]].hair == 0:
				crop_used[local] = 1
			else:
				bun_used[local] = 1
		var everyone := PackedByteArray()
		everyone.resize(seats.size())
		everyone.fill(1)
		var ink := PackedColorArray()
		ink.resize(seats.size())
		ink.fill(FACE_INK)
		section.add_layer(seated_skin, cheer_skin, seats, skin, everyone)
		section.add_layer(seated_cloth, cheer_cloth, seats, cloth, everyone)
		section.add_layer(face, face, seats, ink, everyone)
		section.add_layer(crop, crop, seats, hair, crop_used)
		section.add_layer(bun, bun, seats, hair, bun_used)
		_sections.append(section)
		add_child(section)
	_build_box(started)


func _build_box(started: Array[bool]) -> void:
	var pose := _layout.box_pose()
	var box := Node3D.new()
	box.name = "ImperialBox"
	box.transform = pose
	var names: PackedStringArray = ["Emperor", "Attendant", "Dignitary"]
	var shades: Array[Color] = [RiposteTheme.STONE_BRONZE, RiposteTheme.STONE_LIMESTONE, RiposteTheme.STONE_TERRACOTTA]
	var posed := CrowdMeshes.pose_scene(false)
	var section_index := _layout.section_for(atan2(pose.origin.z, pose.origin.x))
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
			_worn(person, "Face", CrowdMeshes.face(), FACE_INK)
			_worn(person, "Hair", CrowdMeshes.hair(false), HAIR[0])
		else:
			person.mesh = CrowdMeshes.part(false, "skin")
			person.material_override = material
		box.add_child(person)
		var at := pose * person.position
		_include(section_index, at, started)
		_include(section_index, at + Vector3(0.0, 1.4, 0.0), started)
	add_child(box)


func _include(section_index: int, point: Vector3, started: Array[bool]) -> void:
	var box := _bounds[section_index]
	if not started[section_index]:
		box = AABB(point, Vector3(0.2, 0.2, 0.2))
		started[section_index] = true
	else:
		box = box.expand(point)
	_bounds[section_index] = box


func _worn(person: Node3D, part_name: String, mesh: Mesh, ink: Color) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	part.mesh = mesh
	part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := StandardMaterial3D.new()
	material.albedo_color = ink
	material.roughness = 0.85
	part.material_override = material
	person.add_child(part)


func _tint_rendered(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child: Node in node.get_children():
		_tint_rendered(child, material)


func _section_bounds(index: int) -> AABB:
	return _bounds[index]


func _corner(aabb: AABB, index: int) -> Vector3:
	var spot := aabb.position
	if index & 1:
		spot.x += aabb.size.x
	if index & 2:
		spot.y += aabb.size.y
	if index & 4:
		spot.z += aabb.size.z
	return spot
