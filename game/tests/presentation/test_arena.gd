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
	var face := CrowdMeshes.face()
	var crop := CrowdMeshes.hair(false)
	var bun := CrowdMeshes.hair(true)
	assert_true(face != null and crop != null and bun != null, "the head has a face and both hairs")
	var face_box := face.get_aabb()
	var crop_box := crop.get_aabb()
	var bun_box := bun.get_aabb()
	assert_true(face_box.position.y > 0.9, "the eyes sit on the head")
	assert_true(face_box.size.x < 0.2 and face_box.size.z < 0.08, "the face is Wolf's marks, not a second head")
	assert_true(crop_box.position.y > face_box.position.y, "the crop caps the head above the eyes")
	assert_true(crop_box.size.x > 0.2 and crop_box.size.x < 0.34, "the crop covers the crown")
	assert_true(absf(crop_box.size.x - crop_box.size.z) < 0.08, "the crop follows the pentagon, not a flat bar")
	assert_true(bun_box.size.z > crop_box.size.z, "the bun adds the back of the head")


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
	stage.advance(1.0, null, false)
	assert_eq(stage.standing_sections(), 0, "a set point stays seated")
	assert_eq(stage.cheering_count(), 0, "seated energy does not stand anyone")
	stage.reset_poses()
	assert_eq(stage.cheering_count(), 0, "reset sits them down")
	assert_eq(stage.roster_at(0).skin, CrowdRoster.assign(5, 0).skin, "reset does not reshuffle")
	stage.react(CrowdDirector.CUE_VICTORY, 1.0)
	stage.advance(1.0, null, false)
	assert_true(stage.standing_sections() > 0, "a set win stands the bowl")
	assert_true(stage.cheering_count() > 0, "those seats are up")
	var stood := stage.standing_sections()
	stage.react(CrowdDirector.CUE_GASP, 0.2)
	stage.advance(0.2, null, false)
	assert_eq(stage.standing_sections(), stood, "a gasp does not cancel the match celebration")
	assert_eq(stage.batch_count(), batches, "the cheer does not add a batch")
	assert_eq(stage.instance_count(), instances, "the cheer does not add an instance")
	stage.queue_free()


func test_hiding_one_section_keeps_its_cheer() -> void:
	var combat := PackedVector2Array([Vector2(0.4, 0.4), Vector2(0.6, 0.6)])
	var over := PackedVector2Array([Vector2(0.5, 0.5)])
	var aside := PackedVector2Array([Vector2(0.02, 0.02)])
	assert_true(CrowdForeground.overlaps(over, combat, false), "a projected section inside the disc is hidden")
	assert_false(CrowdForeground.overlaps(aside, combat, false), "a projected section outside the disc stays")
	var diamond := PackedVector2Array([Vector2(0.5, 0.2), Vector2(0.8, 0.5), Vector2(0.5, 0.8), Vector2(0.2, 0.5)])
	var corner := PackedVector2Array([Vector2(0.78, 0.22)])
	var middle := PackedVector2Array([Vector2(0.5, 0.5)])
	assert_false(CrowdForeground.overlaps(corner, diamond, false), "a corner of the disc's box is not the disc")
	assert_true(CrowdForeground.overlaps(middle, diamond, false), "the middle of the disc is hidden")
	var stage := CrowdStage.create(9, StandardDuelRules.create().platform_radius)
	stage.focus_section = 2
	stage.hold_chant(true)
	stage.advance(1.0, null, false)
	var cheering := stage.cheering_count()
	assert_true(cheering > 0, "fixture: the chant has seats up")
	(stage.get_child(2) as CrowdSection).set_spectators_hidden(true)
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


func test_the_layout_puts_feet_on_four_treads_and_leaves_the_disc_alone() -> void:
	var rules := StandardDuelRules.create()
	var layout := ArenaSection.load_layout()
	assert_eq(layout.issues().size(), 0, "the shipped layout is valid")
	assert_near(layout.expected_disc_radius, 8.27, 1e-6, "the file records the combat radius")
	assert_true(layout.agrees(rules.platform_radius), "the record matches the rules")
	assert_near(layout.combat_disc(9.0), 9.0, 1e-6, "a disagreement would still use the rules")
	assert_false(layout.agrees(9.0), "9 m does not match the record")
	assert_eq(layout.tier_count(), 4, "four treads")
	assert_eq(layout.course_axis, "east_west", "the paving runs east-west")
	assert_near(layout.curb_height, 0.0, 1e-6, "the fighting surface has no raised edge")
	var raised := ArenaSection.load_layout()
	raised.curb_height = 0.09
	assert_true(raised.issues().size() > 0, "a 9 cm lip is not a flush edge")
	assert_near(layout.foot_offset, 0.09, 1e-6, "the seated mesh minimum is the foot offset")
	assert_near(layout.water_height, RingOutWater.SURFACE_Y, 1e-6, "the basin stays on the existing water line")
	assert_true(layout.seats_clear_piers(), "a pier does not land in front of a seat")
	var previous_height := -1.0
	var previous_outer := 0.0
	for tier: int in layout.tier_count():
		assert_true(layout.tier_outer[tier] > layout.tier_inner[tier], "the tread moves outward")
		assert_true(layout.tier_height[tier] > previous_height, "the tread rises")
		if tier > 0:
			assert_true(layout.tier_inner[tier] >= previous_outer - 0.001, "the next tread starts where the last one ended")
		previous_height = layout.tier_height[tier]
		previous_outer = layout.tier_outer[tier]
	var broken := ArenaSection.load_layout()
	var heights := broken.tier_height
	heights[3] = heights[0]
	broken.tier_height = heights
	assert_true(broken.issues().size() > 0, "a tread that does not rise fails the check")
	var stage := CrowdStage.create(5, rules.platform_radius)
	var again := CrowdStage.create(5, rules.platform_radius)
	var seats := stage.placed_origins()
	var repeated := again.placed_origins()
	var expected := 0
	for tier: int in layout.tier_count():
		expected += layout.tier_seat_count[tier]
	assert_eq(seats.size(), expected, "one seat per authored place")
	assert_eq(repeated.size(), seats.size(), "the same seed builds the same count")
	assert_true(seats[0].is_equal_approx(repeated[0]), "the same seed builds the same first seat")
	for origin: Vector3 in seats:
		assert_true(_on_tread(origin, layout), "feet at (%.3f, %.3f, %.3f) stay on a tread" % [origin.x, origin.y, origin.z])
	var box := stage.get_node("ImperialBox") as Node3D
	assert_near(box.position.y + layout.foot_offset, layout.tier_height[layout.tier_count() - 1], 0.001, "the box stands on the outer tread")
	assert_true(box.position.z > layout.tier_inner[layout.tier_count() - 1], "the box is on the south stands")
	assert_true(absf(box.position.x) < 1.0, "the box is centred on the south opening")
	stage.free()
	again.free()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var first := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, 2.0, 4)
	var crowd_count := first.crowd().instance_count()
	first.free()
	var arena := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, 2.0, 4)
	assert_eq(arena.crowd().instance_count(), crowd_count, "a new scaffold does not keep the previous crowd")
	assert_eq(_bodies(arena), 1, "the floor and the bowl add no collider")
	var worlds := 0
	for child: Node in arena.get_children():
		if child is WorldEnvironment:
			worlds += 1
	assert_eq(worlds, 1, "one environment owns the match")
	var env := arena.get_node("Environment") as WorldEnvironment
	assert_eq(env.environment.background_mode, Environment.BG_SKY, "the match sky is outdoor")
	var sky_mat := env.environment.sky.sky_material as ProceduralSkyMaterial
	assert_true(sky_mat != null, "the sky is procedural")
	assert_eq(sky_mat.sky_top_color, RiposteTheme.SKY_TOP, "the overhead color is the theme")
	assert_near(sky_mat.sun_angle_max, 0.0, 1e-4, "the sky draws no sun disc")
	assert_eq(env.environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "the sky does not relight the fighters")
	assert_false((arena.get_node("KeyLight") as DirectionalLight3D).shadow_enabled, "the key stays shadowless")
	assert_false((arena.get_node("RimLight") as DirectionalLight3D).shadow_enabled, "the rim stays shadowless")
	var paving := arena.get_node_or_null("SandSurface")
	var bowl := arena.get_node_or_null("Bowl")
	assert_true(paving != null, "the sand disc is on the scaffold")
	assert_true(bowl != null, "the bowl is instanced")
	var top := _find(arena, "PlatformTop") as Node3D
	assert_true(top != null, "the rollback disc is still in the authored scene")
	assert_false(top.visible, "the plug is hidden while the sand disc is shown")
	assert_false(ArenaScaffold.is_stand_in("PlatformTop"), "the disc is not an ornamental stand-in")
	assert_true(ArenaScaffold.is_replaced_disc("PlatformTop"), "the disc is the surface the floor replaces")
	var edge := arena.get_node("EdgeStrip") as MeshInstance3D
	var torus := edge.mesh as TorusMesh
	assert_near(torus.outer_radius, layout.curb_inner_radius, 1e-4, "the warning strip stops at the curb")
	_assert_sand(paving, rules.platform_radius)
	_assert_bowl(bowl, layout)
	arena.free()


func _on_tread(origin: Vector3, layout: ArenaSection) -> bool:
	var radius := Vector2(origin.x, origin.z).length()
	for tier: int in layout.tier_count():
		if absf(origin.y + layout.foot_offset - layout.tier_height[tier]) > 0.001:
			continue
		if radius > layout.tier_inner[tier] - 0.05 and radius < layout.tier_outer[tier] + 0.05:
			return true
	return false


func _assert_sand(paving: Node, platform_radius: float) -> void:
	var top := paving.get_node("Top") as MeshInstance3D
	var disc := top.mesh as CylinderMesh
	assert_near(disc.top_radius, platform_radius, 1e-4, "the sand disc is the combat radius")
	var side := paving.get_node("Side") as MeshInstance3D
	for instance: MeshInstance3D in [top, side]:
		var mesh := instance.mesh
		var xform := _chain(instance)
		for surface_index: int in mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := xform * vertex
				assert_true(point.y <= 0.008, "nothing on the fighting surface stands above the plane")
	assert_eq(_bodies(paving), 0, "the sand disc adds no collider")


func _assert_bowl(bowl: Node, layout: ArenaSection) -> void:
	var disc := layout.expected_disc_radius
	var soffit := layout.floor_soffit
	var first := layout.tier_height[0]
	var second := layout.tier_inner[1]
	var top := layout.tier_height[layout.tier_count() - 1]
	var water_center := false
	var water_rim := false
	for instance: MeshInstance3D in _meshes_under(bowl):
		var mesh := instance.mesh
		if mesh == null:
			continue
		var xform := _chain(instance)
		for surface: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := xform * vertex
				var radius := Vector2(point.x, point.z).length()
				assert_true(radius > disc + 0.05 or point.y <= 0.02, "supports under the disc stay below the fighting surface")
				assert_true(radius >= layout.outer_inner_radius - 0.05 or point.y <= soffit + 0.05, "no crown rises above the soffit inside the moat")
				assert_true(point.y <= first + 0.05 or radius >= second - 0.08, "upper treads stay behind the first row")
				assert_true(point.y <= top + 0.05, "nothing stands above the top tread")
				if absf(point.y - layout.water_height) < 0.05 and radius < 1.0:
					water_center = true
				if absf(point.y - layout.water_height) < 0.05 and radius > layout.outer_outer_radius - 0.3:
					water_rim = true
	assert_true(water_center, "water covers the ground under the inner arcade")
	assert_true(water_rim, "water reaches the outer tread")


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_meshes_under(child))
	return found


func _chain(node: Node3D) -> Transform3D:
	var above := node.get_parent()
	if above is Node3D:
		return _chain(above as Node3D) * node.transform
	return node.transform


func _find(node: Node, wanted: String) -> Node:
	if String(node.name) == wanted:
		return node
	for child: Node in node.get_children():
		var found := _find(child, wanted)
		if found != null:
			return found
	return null


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
