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
	var dead := MeshInstance3D.new()
	dead.name = "DeadEye.L.A"
	root.add_child(alive)
	root.add_child(dead)
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	return {"root": root, "eye": alive, "dead": dead}


func test_a_living_fighter_shows_the_eyes() -> void:
	var figure := _figure()
	FacePresentation.apply(figure["root"], true)
	assert_true(figure["eye"].visible, "the living eye is shown")
	assert_false(figure["dead"].visible, "the X is hidden")
	figure["root"].free()


func test_death_keeps_the_x_until_a_new_figure() -> void:
	var figure := _figure()
	FacePresentation.apply(figure["root"], false)
	FacePresentation.apply(figure["root"], false)
	assert_false(figure["eye"].visible, "the living eye stays hidden")
	assert_true(figure["dead"].visible, "the X stays through another update")
	var rematch := _figure()
	FacePresentation.apply(rematch["root"], true)
	assert_true(rematch["eye"].visible, "a new presentation starts alive")
	assert_false(figure["eye"].visible, "the corpse is unchanged")
	figure["root"].free()
	rematch["root"].free()


## The exported Ranger and Training bodies carry both faces, and the production
## proxy selects from the projected terminal: a kill, a ring-out, and a new proxy.
func test_the_exported_bodies_and_the_proxy_share_one_face_contract() -> void:
	var rules := StandardDuelRules.create()
	for scene_path: String in ["res://assets/generated/fighters/wolf.glb", "res://assets/generated/fighters/wolf_training.glb"]:
		var scene := (load(scene_path) as PackedScene).instantiate()
		assert_true(_parts(scene, "Eye").size() >= 2, "%s has living eyes" % scene_path.get_file())
		assert_true(_parts(scene, "DeadEye").size() >= 2, "%s has the X" % scene_path.get_file())
		scene.free()
	var living := _proxy(&"", rules)
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
	_pose(fallen, ring_row)
	_assert_face(fallen, false)
	var training := _proxy(RiposteKits.SKIN_DUELIST_TRAINING, rules)
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
	var dead := _parts(proxy, "DeadEye")
	assert_true(eyes.size() >= 2 and dead.size() >= 2, "the proxy is carrying both faces")
	for eye: Node in eyes:
		assert_eq(eye.visible, alive, "living eyes follow the terminal")
	for mark: Node in dead:
		assert_eq(mark.visible, not alive, "the X follows the terminal")


func _parts(root: Node, prefix: String) -> Array[Node]:
	var found: Array[Node] = []
	var part := String(root.name)
	if part.begins_with(prefix) and not (prefix == "Eye" and part.begins_with("DeadEye")):
		found.append(root)
	for child in root.get_children():
		found.append_array(_parts(child, prefix))
	return found
