extends TestCase

## PRES-FACE: death replaces the eyes with X marks and a new presentation
## starts alive again. The swap does not read or write combat state.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-FACE"


func _figure() -> Dictionary:
	var root := Node3D.new()
	root.name = "Figure"
	var alive := MeshInstance3D.new()
	alive.name = "Eye.L"
	var brow := MeshInstance3D.new()
	brow.name = "Brow"
	var dead := MeshInstance3D.new()
	dead.name = "DeadEye.L.A"
	root.add_child(alive)
	root.add_child(brow)
	root.add_child(dead)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	return {"root": root, "eye": alive, "brow": brow, "dead": dead}


func test_a_living_fighter_shows_the_eyes() -> void:
	var figure := _figure()
	FacePresentation.apply(figure["root"], true)
	assert_true(figure["eye"].visible, "the living eye is shown")
	assert_true(figure["brow"].visible, "the brow stays")
	assert_false(figure["dead"].visible, "the X is hidden")
	figure["root"].free()


func test_death_keeps_the_x_until_a_new_figure() -> void:
	var figure := _figure()
	FacePresentation.apply(figure["root"], false)
	FacePresentation.apply(figure["root"], false)
	assert_false(figure["eye"].visible, "the living eye stays hidden")
	assert_true(figure["brow"].visible, "the brow is not the X")
	assert_true(figure["dead"].visible, "the X stays through another update")
	var rematch := _figure()
	FacePresentation.apply(rematch["root"], true)
	assert_true(rematch["eye"].visible, "a new presentation starts alive")
	assert_true(rematch["brow"].visible, "and keeps the brow")
	assert_false(rematch["dead"].visible, "with no leftover X")
	assert_false(figure["eye"].visible, "the corpse is unchanged")
	figure["root"].free()
	rematch["root"].free()


## Blend-shape weights are stored as 32-bit floats.
const WEIGHT_TOLERANCE := 1e-6
const CHANNELS: Array[String] = ["brow_inner_down", "brow_outer_up", "lid_upper_close", "lid_upper_open", "gaze_left", "gaze_right", "gaze_up", "gaze_down", "blink"]


func _keyed_mesh(part: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for key in CHANNELS:
		mesh.add_blend_shape(key)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
	var shapes: Array[Array] = []
	for _key in CHANNELS:
		var shape := []
		shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3(0.0, 2.0, 0.0)])
		shapes.append(shape)
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, shapes)
	var node := MeshInstance3D.new()
	node.name = part
	node.mesh = mesh
	return node


func _weight(node: MeshInstance3D, key: String) -> float:
	return node.get_blend_shape_value(node.find_blend_shape_by_name(key))


## FACE-EXPRESSION-001 / FACE-EYE-001: a preset weights its channels per side
## (designed asymmetry), on brows and lids together; gaze and the blink are
## channels too; dead is the X with neutral brows; neutral clears every channel.
func test_presets_weight_the_channels_per_side() -> void:
	## ARRANGE: a face whose left and right brow and upper lid carry the channels.
	var root := Node3D.new()
	var brow_l := _keyed_mesh("Brow_L")
	var brow_r := _keyed_mesh("Brow_R")
	var lid_l := _keyed_mesh("EyeLidUpper_L")
	var dead := MeshInstance3D.new()
	dead.name = "DeadEye_L_A"
	for node: Node in [brow_l, brow_r, lid_l, dead]:
		root.add_child(node)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var parts := FacePresentation.bind(root)
	assert_eq(parts.size(), 4, "fixture: both brows, a lid and the X are bound")
	var left: Dictionary = FacePresentation.PRESETS[FacePresentation.AGGRESSIVE]["L"]
	var right: Dictionary = FacePresentation.PRESETS[FacePresentation.AGGRESSIVE]["R"]
	assert_true(left["brow_inner_down"] != right["brow_inner_down"], "fixture: aggressive is asymmetric")
	## ACT
	FacePresentation.show_expression(parts, FacePresentation.AGGRESSIVE)
	## ASSERT: each side carries its own weights; a channel the preset does not name stays 0.
	assert_near(_weight(brow_l, "brow_inner_down"), float(left["brow_inner_down"]), WEIGHT_TOLERANCE, "the left brow compresses by the left weight")
	assert_near(_weight(brow_r, "brow_inner_down"), float(right["brow_inner_down"]), WEIGHT_TOLERANCE, "the right brow by the right weight")
	assert_near(_weight(lid_l, "lid_upper_close"), float(left["lid_upper_close"]), WEIGHT_TOLERANCE, "the lid closes with the brow")
	assert_eq(_weight(lid_l, "lid_upper_open"), 0.0, "an unnamed channel stays at rest")
	assert_false(dead.visible, "aggressive hides the X")
	## PERTURB: a half blend, a gaze up and to the character's left, a blink.
	FacePresentation.pose(parts, FacePresentation.ALERT, 0.5, Vector2(0.6, 0.3), 1.0)
	var alert: Dictionary = FacePresentation.PRESETS[FacePresentation.ALERT]["L"]
	assert_near(_weight(brow_l, "brow_outer_up"), float(alert["brow_outer_up"]) * 0.5, WEIGHT_TOLERANCE, "a blend is partial")
	assert_near(_weight(lid_l, "gaze_left"), 0.6, WEIGHT_TOLERANCE, "the gaze is a channel")
	assert_eq(_weight(lid_l, "gaze_right"), 0.0, "the opposite gaze is off")
	assert_near(_weight(lid_l, "gaze_up"), 0.0, WEIGHT_TOLERANCE, "a closed eye drops the vertical gaze (it moves the edges)")
	assert_eq(_weight(lid_l, "blink"), 1.0, "the blink closes the lid")
	assert_true(float(alert["lid_upper_open"]) > 0.0, "fixture: alert opens the lid")
	assert_eq(_weight(lid_l, "lid_upper_open"), 0.0, "a full blink closes from rest: the preset's lid channels fade out")
	FacePresentation.pose(parts, FacePresentation.ALERT, 1.0, Vector2(0.0, 0.4), 0.5)
	assert_near(_weight(lid_l, "gaze_up"), 0.2, WEIGHT_TOLERANCE, "the lids follow the gaze up, half through a half blink")
	assert_near(_weight(lid_l, "lid_upper_open"), float(alert["lid_upper_open"]) * 0.5, WEIGHT_TOLERANCE, "a half blink keeps half the lid")
	assert_near(_weight(brow_l, "brow_outer_up"), float(alert["brow_outer_up"]), WEIGHT_TOLERANCE, "the brows keep the expression through a blink")
	FacePresentation.show_expression(parts, FacePresentation.DEAD)
	assert_false(lid_l.visible, "dead hides the eye assembly")
	assert_true(dead.visible, "dead shows the X")
	assert_true(brow_l.visible, "dead keeps the brow")
	for key in CHANNELS:
		assert_eq(_weight(brow_l, key), 0.0, "dead brows are neutral: %s" % key)
	FacePresentation.show_expression(parts, FacePresentation.NEUTRAL)
	for key in CHANNELS:
		assert_eq(_weight(lid_l, key), 0.0, "neutral clears %s" % key)
	assert_true(lid_l.visible and not dead.visible, "neutral is the living face")
	root.free()


## The exported Ranger and Training bodies carry both faces, and the production
## proxy selects from the projected terminal: a kill, a ring-out, and a new proxy.
func test_the_exported_bodies_and_the_proxy_share_one_face_contract() -> void:
	var rules := StandardDuelRules.create()
	for scene_path: String in ["res://assets/generated/fighters/wolf.glb", "res://assets/generated/fighters/wolf_training.glb"]:
		var scene := (load(scene_path) as PackedScene).instantiate()
		assert_true(_parts(scene, "Eye").size() >= 2, "%s has living eyes" % scene_path.get_file())
		assert_true(_parts(scene, "Brow").size() >= 1, "%s has the brow" % scene_path.get_file())
		assert_true(_parts(scene, "DeadEye").size() >= 2, "%s has the X" % scene_path.get_file())
		scene.free()
	var living := _proxy(&"", rules)
	await await_frames(1)
	_assert_face(living, true)
	var killed := DuelSetup.new_state(rules, 3)
	killed.fighter(0).health = 0.0
	var dead_row := SnapshotProjector.project(killed, rules).fighter(0)
	assert_eq(dead_row.terminal_cause, FighterState.Terminal.KILLED, "fixture: no health is a kill")
	_pose(living, dead_row)
	_pose(living, dead_row)
	_assert_face(living, false)
	var ring_state := DuelSetup.new_state(rules, 3)
	ring_state.fighter(0).lose_support(0.2)
	var ring_row := SnapshotProjector.project(ring_state, rules).fighter(0)
	assert_eq(ring_row.terminal_cause, FighterState.Terminal.RING_OUT, "fixture: a supported loss with health left is a ring-out")
	assert_true(ring_row.health > 0.0, "fixture: the ring-out is not a kill")
	var fallen := _proxy(&"", rules)
	await await_frames(1)
	_pose(fallen, ring_row)
	_assert_face(fallen, false)
	var training := _proxy(RiposteKits.SKIN_DUELIST_TRAINING, rules)
	await await_frames(1)
	_assert_face(training, true)
	_pose(training, dead_row)
	_assert_face(training, false)
	var rematch := _proxy(&"", rules)
	_assert_face(rematch, true)
	_assert_face(living, false)
	for proxy: Node in [living, fallen, training, rematch]:
		proxy.free()


func _proxy(skin: StringName, rules: DuelRules) -> FighterPresentation3D:
	var skins: Array[StringName] = [skin, &""]
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules, skins)
	var proxy := FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), rules.combatant(0).fighter.push_radius, rules.combatant(0))
	(Engine.get_main_loop() as SceneTree).root.add_child(proxy)
	return proxy


func _pose(proxy: FighterPresentation3D, row: PresentationFighter) -> void:
	row.target_bearing = row.facing
	proxy.apply_pose(Vector3.ZERO, row.facing, row.weapon_angle, row, 1.0 / 60.0)


func _assert_face(proxy: Node, alive: bool) -> void:
	var eyes := _parts(proxy, "Eye")
	var brows := _parts(proxy, "Brow")
	var dead := _parts(proxy, "DeadEye")
	assert_true(eyes.size() >= 2 and dead.size() >= 2, "the proxy is carrying both faces")
	assert_true(brows.size() >= 1, "and the brow bar")
	for eye: Node in eyes:
		assert_eq(eye.visible, alive, "living eyes follow the terminal")
	for brow: Node in brows:
		assert_true(brow.visible, "the brow stays through the terminal")
	for mark: Node in dead:
		assert_eq(mark.visible, not alive, "the X follows the terminal")
	if not alive:
		_assert_x_covers_eyes_not_brows(eyes, brows, dead)


func _assert_x_covers_eyes_not_brows(eyes: Array[Node], brows: Array[Node], marks: Array[Node]) -> void:
	var eye := _merged_aabb(eyes)
	var brow := _merged_aabb(brows)
	var mark := _merged_aabb(marks)
	assert_true(mark.size.y > 0.015, "the X stands in the face plane, not as a flat slash")
	assert_true(mark.intersects(eye), "the X occupies the living-eye band")
	assert_false(mark.intersects(brow), "and does not replace the brow")


func _merged_aabb(nodes: Array[Node]) -> AABB:
	var merged := AABB()
	var started := false
	for node in nodes:
		if not node is MeshInstance3D:
			continue
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		if not started:
			merged = box
			started = true
		else:
			merged = merged.merge(box)
	assert_true(started, "fixture: face parts are meshes")
	return merged


func _parts(root: Node, prefix: String) -> Array[Node]:
	var found: Array[Node] = []
	var part := String(root.name)
	if part.begins_with(prefix) and not (prefix == "Eye" and part.begins_with("DeadEye")):
		found.append(root)
	for child in root.get_children():
		found.append_array(_parts(child, prefix))
	return found
