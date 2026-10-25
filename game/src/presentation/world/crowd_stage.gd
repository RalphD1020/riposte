class_name CrowdStage
extends Node3D

## The bowl's spectators: the stage's `CrowdProfile` (its figures and
## palettes) seated by `ArenaSection`. During a match they
## stay in their seats and stay drawn: a section is not removed when its box
## crosses the fight on screen. They rock, and a shifting share swap to the
## arms-up mesh. A louder room keeps more arms up. A name chant stands the
## sections on that fighter's side of the bowl. The match result stands
## everyone. A round roar does not. Reduced motion drops the seated wave and
## still lets a stand finish. Rematch builds a new stage.
##
## See also: /docs/concepts/presentation.md

const SETTLE_SECONDS := 0.2
const MOVE_EPSILON := 0.04
const FIGURE_GAP := 0.7
## Sections within this ring distance of the named fighter's side stand.
const CHANT_SPAN := 1
## Stable offset so neighboring sections do not lean on the same beat.
const SECTION_PHASE := 1.3

var seed_value: int = 1
var focus_section: int = 0

var _profile: CrowdProfile
var _sections: Array[CrowdSection] = []
var _rows: Array[CrowdRoster] = []
var _layout: ArenaSection
var _bounds: Array[AABB] = []
var _origins := PackedVector3Array()
var _camera_at := Vector3.INF
var _still := 0.0
var _excitement := 0.0
var _chant := false
var _match_celebration := false


static func create(audience: CrowdProfile, p_seed: int) -> CrowdStage:
	var stage := CrowdStage.new()
	stage.name = "Crowd"
	stage._profile = audience
	stage.seed_value = p_seed if p_seed != 0 else 1
	stage._build()
	return stage


func profile() -> CrowdProfile:
	return _profile


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


func _build() -> void:
	_layout = ArenaSection.load_layout()
	if not _layout.issues().is_empty():
		return
	var seated_skin := _profile.part(false, "skin")
	var cheer_skin := _profile.part(true, "skin")
	var seated_cloth := _profile.part(false, "fabric")
	var cheer_cloth := _profile.part(true, "fabric")
	var seated_leather := _profile.part(false, "leather")
	var cheer_leather := _profile.part(true, "leather")
	var hairs: Array[Mesh] = []
	for style: int in _profile.hair_scenes.size():
		hairs.append(_profile.hair_style(style))
	var beards: Array[Mesh] = []
	for style: int in _profile.beard_scenes.size():
		beards.append(_profile.beard_style(style))
	var face := _profile.face()
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
		var leather := PackedColorArray()
		var hair := PackedColorArray()
		var which: PackedInt32Array = []
		for seat: int in poses.size():
			if seat_section[seat] != index:
				continue
			seats.append(poses[seat])
			which.append(seat)
			skin.append(_tone(_profile.skin, _rows[seat].skin))
			cloth.append(_tone(_profile.cloth, _rows[seat].cloth))
			leather.append(_tone(_profile.leather, _rows[seat].cloth))
			hair.append(_tone(_profile.hair, _rows[seat].hair_color))
		if seats.is_empty():
			_sections.append(section)
			add_child(section)
			continue
		var hair_used: Array[PackedByteArray] = []
		for _style: int in hairs.size():
			var used := PackedByteArray()
			used.resize(seats.size())
			hair_used.append(used)
		var beard_used: Array[PackedByteArray] = []
		for _style: int in beards.size():
			var used := PackedByteArray()
			used.resize(seats.size())
			beard_used.append(used)
		for local: int in which.size():
			var row := _rows[which[local]]
			if not row.bald:
				var style := row.hair % hairs.size()
				hair_used[style][local] = 1
			if row.beard > 0 and not beards.is_empty():
				beard_used[row.beard % beards.size()][local] = 1
		var everyone := PackedByteArray()
		everyone.resize(seats.size())
		everyone.fill(1)
		var ink := PackedColorArray()
		ink.resize(seats.size())
		ink.fill(_profile.face_ink)
		section.add_layer(seated_skin, cheer_skin, seats, skin, everyone)
		section.add_layer(seated_cloth, cheer_cloth, seats, cloth, everyone)
		section.add_layer(seated_leather, cheer_leather, seats, leather, everyone)
		section.add_layer(face, face, seats, ink, everyone)
		for style: int in hairs.size():
			section.add_layer(hairs[style], hairs[style], seats, hair, hair_used[style])
		for style: int in beards.size():
			section.add_layer(beards[style], beards[style], seats, hair, beard_used[style])
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
	var posed := _profile.pose_scene(false)
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
			_worn(person, "Face", _profile.face(), _profile.face_ink)
			_worn(person, "Hair", _profile.hair_style(0), _profile.hair[0])
		else:
			person.mesh = _profile.part(false, "skin")
			person.material_override = material
		box.add_child(person)
		var at := pose * person.position
		_include(section_index, at, started)
		_include(section_index, at + Vector3(0.0, 1.4, 0.0), started)
	add_child(box)


## A roster index into a palette of any length.
static func _tone(palette: PackedColorArray, index: int) -> Color:
	return palette[index % palette.size()]


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


## Spectators never cast into the key's shadow map.
func _tint_rendered(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
		(node as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_tint_rendered(child, material)

