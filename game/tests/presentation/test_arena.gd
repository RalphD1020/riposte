extends TestCase

## PRES-ARENA: the bowl is presentation. The disc, the fall's root, and Wolf's
## skin stay put. Seats are a pure function of the seed. A cheer moves seats
## that already exist.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-ARENA"


func test_the_same_seed_seats_the_same_people() -> void:
	var first := CrowdRoster.assign(11, 4)
	var again := CrowdRoster.assign(11, 4)
	assert_eq(again.skin, first.skin, "skin is the seed and the seat")
	assert_eq(again.role, first.role, "role is the seed and the seat")
	assert_eq(again.hair, first.hair, "hair is the seed and the seat")
	var raw := CrowdRoster.assign(11, 5)
	var forced := CrowdRoster.new()
	forced.skin = raw.skin
	forced.role = raw.role
	forced.hair = raw.hair
	var neighbor := CrowdRoster.assign(11, 5, forced)
	assert_eq(neighbor.skin, raw.skin, "the bump keeps the skin")
	assert_false(neighbor.hair == raw.hair, "a copied neighbor gets the other hair")
	var weights := 0
	for weight: int in CrowdRoster.SKIN_WEIGHTS:
		weights += weight
	assert_eq(weights, 100, "the skin draw covers every seat")


func test_a_living_fall_follows_root_at_until_the_basin() -> void:
	var exit := Vector3(8.3, 0.0, 0.2)
	var velocity := Vector3(1.5, 0.0, 0.0)
	var request := FallPresentationRequest.create(0, exit, velocity, 3)
	var early := 0.4
	assert_true(RingOutWater.shown(request, early, false).is_equal_approx(request.root_at(early)), "before the water the drawing is the ballistic root")
	var entry := RingOutWater.entry_time(request)
	var at_entry := request.root_at(entry)
	assert_true(RingOutWater.shown(request, entry, true).is_equal_approx(at_entry), "at the water the drawing still is the ballistic root")
	var drifted := RingOutWater.shown(request, entry + 0.05, true)
	assert_true(absf(drifted.x - at_entry.x) > 0.01, "horizontal speed carries on instead of stopping in one frame")
	assert_true(drifted.distance_to(at_entry) < 1.0, "the ease does not teleport the body")
	var deep := request.root_at(entry + 1.0)
	var floating := RingOutWater.shown(request, entry + 1.0, true)
	assert_true(deep.y < floating.y, "the root keeps falling after the drawing has eased")
	assert_near(request.root_at(0.4).y, -0.5 * FallPresentationRequest.GRAVITY * 0.16, 1e-4, "root_at itself is unchanged")
	var bobbed := RingOutWater.shown(request, entry + 0.4, false)
	var still := RingOutWater.shown(request, entry + 0.4, true)
	assert_false(is_equal_approx(bobbed.y, still.y), "reduced motion drops the bob")
	assert_eq(RiposteTheme.WORLD_FLOOR, Color("8a7f6c"), "the combat floor color is unchanged")


func test_a_cheer_does_not_allocate_and_a_finish_moves_more_seats() -> void:
	var stage := CrowdStage.create(5, StandardDuelRules.create().platform_radius)
	var batches := stage.batch_count()
	var instances := stage.instance_count()
	stage.react(CrowdDirector.CUE_SETPOINT, 0.3)
	var small := stage.cheering_count()
	assert_true(small > 0, "a set point lifts a few seats")
	stage.reset_poses()
	assert_eq(stage.cheering_count(), 0, "reset sits them down")
	assert_eq(stage.roster_at(0).skin, CrowdRoster.assign(5, 0).skin, "reset does not reshuffle")
	stage.react(CrowdDirector.CUE_VICTORY, 1.0)
	assert_true(stage.cheering_count() > small, "a set win moves more seats than a set point")
	stage.react(CrowdDirector.CUE_GASP, 0.2)
	var after_gasp := stage.cheering_count()
	stage.advance(0.0, null, false)
	assert_eq(stage.cheering_count(), after_gasp, "a gasp does not add a cheer")
	assert_eq(stage.batch_count(), batches, "the cheer does not add a batch")
	assert_eq(stage.instance_count(), instances, "the cheer does not add an instance")
	stage.queue_free()


func test_hiding_one_section_keeps_its_cheer() -> void:
	var combat := PackedVector2Array([Vector2(0.4, 0.4), Vector2(0.6, 0.6)])
	var over := PackedVector2Array([Vector2(0.5, 0.5)])
	var aside := PackedVector2Array([Vector2(0.02, 0.02)])
	assert_true(CrowdForeground.overlaps(over, combat, false), "a projected section inside the disc is hidden")
	assert_false(CrowdForeground.overlaps(aside, combat, false), "a projected section outside the disc stays")
	var stage := CrowdStage.create(9, StandardDuelRules.create().platform_radius)
	stage.focus_section = 2
	stage.react(CrowdDirector.CUE_CHEER, 0.6)
	var cheering := stage.cheering_count()
	(stage.get_child(2) as CrowdSection).set_spectators_hidden(true)
	assert_eq(stage.cheering_count(), cheering, "hiding a section does not clear its cheer")
	assert_false(stage.section_hidden(3), "the next section stays visible")
	stage.queue_free()


func test_the_scaffold_adds_no_collider_and_a_missing_part_is_named() -> void:
	var rules := StandardDuelRules.create()
	assert_near(rules.platform_radius, 8.27, 1e-6, "the disc radius is unchanged")
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var arena := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, 2.0, 4)
	assert_eq(_bodies(arena), 1, "only the presentation disc collides")
	var shape := (arena.presentation_ground().get_child(0) as CollisionShape3D).shape as CylinderShape3D
	assert_near(shape.radius, rules.platform_radius, 1e-6, "that disc is the platform")
	var missing := CrowdMeshes.part(false, "absent")
	assert_eq(missing.resource_name, "fallback.absent", "a missing part uses the named fallback")
	var text := FileAccess.get_file_as_string("res://content/characters/wolf.character.json")
	assert_true(text.contains("\"skin\""), "fixture: Wolf's palette is in the file")
	assert_true(text.contains("0.87") and text.contains("0.71") and text.contains("0.6"), "Wolf's palette.skin is unchanged")
	var parsed: Variant = JSON.parse_string(text)
	var swatches: Dictionary = (parsed as Dictionary)["skin_swatches"]
	assert_eq(CrowdStage.SKIN.size(), swatches.size(), "the crowd uses every authored swatch")
	for index: int in CrowdStage.SKIN.size():
		var rgb: Array = swatches["skin_%02d" % (index + 1)]
		assert_near(CrowdStage.SKIN[index].r, float(rgb[0]), 0.002, "skin_%02d red matches the file" % (index + 1))
	assert_true(ArenaScaffold.is_stand_in("Pillar3"), "the ornamental pillar is a stand-in")
	assert_false(ArenaScaffold.is_stand_in("PierL"), "a structural pier is not a stand-in")
	assert_false(ArenaScaffold.is_stand_in("Bay00_stone_pillar"), "a bowl material mesh is not a stand-in")
	var bowl := arena.get_node_or_null("Bowl")
	if bowl != null:
		assert_true(bowl.visible, "the bowl stays visible")
	var emperor := arena.crowd().get_node("ImperialBox/Emperor")
	var tinted := _rendered_override(emperor)
	assert_true(tinted != null, "the emperor tint is on a rendered mesh")
	assert_true((tinted as StandardMaterial3D).albedo_color.is_equal_approx(RiposteTheme.STONE_BRONZE), "that mesh wears the bronze")
	arena.free()


func _rendered_override(node: Node) -> Material:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and mesh_node.material_override != null:
			return mesh_node.material_override
	for child: Node in node.get_children():
		var found := _rendered_override(child)
		if found != null:
			return found
	return null


func _bodies(node: Node) -> int:
	var count := 1 if node is StaticBody3D else 0
	for child: Node in node.get_children():
		count += _bodies(child)
	return count
