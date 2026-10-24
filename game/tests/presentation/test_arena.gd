extends TestCase

## PRES-ARENA: the bowl is presentation. The disc, the fall's root, and Wolf's
## skin stay put. Seats are a pure function of the seed. A cheer moves seats
## that already exist.
##
## See also: /docs/concepts/presentation.md


## A water surface only this fixture requests. No shipped stage has one.
const WATER_FIXTURE := -3.0

var _roman_profile: CrowdProfile


func _init() -> void:
	suite_name = "PRES-ARENA"


## The crowd the Arena's kit seats, read the way the scaffold reads it.
func _roman() -> CrowdProfile:
	if _roman_profile == null:
		var kits := DuelKits.resolve(RiposteKits.build_catalog(), StandardDuelRules.create())
		_roman_profile = ArenaScaffold.profile_of(kits.arena).crowd
	return _roman_profile


func _kits_for(arena_id: StringName) -> DuelKits:
	var rules := StandardDuelRules.create()
	rules.arena_id = arena_id
	return DuelKits.resolve(RiposteKits.build_catalog(), rules)


## A stage seats the crowd its profile names, or nobody (ART-CROWD-002): the
## Arena its Roman crowd, The End nobody. A scaffold built for the next stage
## never carries the last one's crowd, and the stage list agrees with what
## presentation builds.
func test_each_stage_seats_the_crowd_its_profile_names() -> void:
	var rules := StandardDuelRules.create()
	var roman := _roman()
	assert_true(roman != null, "the Arena names a crowd")
	assert_eq(roman.problem(), "", "every scene and palette that crowd draws exists")
	var styles := {}
	for index: int in roman.hair_scenes.size():
		var mesh := roman.hair_style(index)
		assert_false(String(mesh.resource_name).begins_with(CrowdMeshes.FALLBACK), "hairstyle %d is its exported mesh" % index)
		styles[mesh.get_instance_id()] = true
	assert_eq(styles.size(), roman.hair_scenes.size(), "every hairstyle is its own mesh")
	var arena_kits := _kits_for(ContentIds.ARENA_STANDARD)
	var end_kits := _kits_for(ContentIds.ARENA_END)
	assert_true(ArenaScaffold.profile_of(end_kits.arena).crowd == null, "The End names no crowd")
	var arena := ArenaScaffold.create(arena_kits.arena, rules.platform_radius, rules.edge_warning_inset, 2.0, 4)
	assert_true(arena.crowd() != null and arena.crowd().profile() == roman, "the Arena scaffold seats that crowd")
	arena.free()
	var deck := ArenaScaffold.create(end_kits.arena, rules.platform_radius, rules.edge_warning_inset, 2.0, 4)
	assert_true(deck.crowd() == null and deck.get_node_or_null("Crowd") == null, "the next stage's scaffold seats nobody")
	deck.free()
	var again := ArenaScaffold.create(arena_kits.arena, rules.platform_radius, rules.edge_warning_inset, 2.0, 4)
	assert_true(again.crowd() != null and again.crowd().instance_count() > 0, "back on the Arena the crowd is built fresh")
	again.free()
	for stage: StageDefinition in [StageCatalog.arena(), StageCatalog.the_end(), StageCatalog.open_disc()]:
		var kits := _kits_for(stage.kit_id)
		assert_eq(ArenaScaffold.profile_of(kits.arena).crowd != null, stage.has_crowd, "%s: the stage list and the kit agree on a crowd" % stage.display_name)
	var deck_profile := ArenaScaffold.profile_of(end_kits.arena).duplicate() as StagePresentationProfile
	assert_eq(deck_profile.problem(), "", "fixture: The End's profile is valid")
	deck_profile.crowd = roman
	assert_eq(deck_profile.problem(), "a deck has no bowl to seat a crowd in", "a deck refuses a crowd")
	var short := roman.duplicate() as CrowdProfile
	short.hair_scenes = PackedStringArray([roman.hair_scenes[0], roman.hair_scenes[0]])
	assert_true(short.problem().begins_with("a hairstyle is listed twice"), "one file cannot stand in for two hairstyles")
	short.hair_scenes = PackedStringArray([roman.hair_scenes[0], "res://assets/generated/crowd/absent.glb"])
	assert_true(short.problem().begins_with("a hairstyle is missing"), "a missing hairstyle fails instead of borrowing another")


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
	var face := _roman().face()
	var crop := _roman().hair_style(0)
	var bun := _roman().hair_style(1)
	assert_true(face != null and crop != null and bun != null, "the head has a face and both hairs")
	var face_box := face.get_aabb()
	var crop_box := crop.get_aabb()
	var bun_box := bun.get_aabb()
	assert_true(face_box.position.y > 0.9, "the eyes sit on the head")
	assert_true(face_box.size.x < 0.2 and face_box.size.z < 0.08, "the face is Wolf's marks, not a second head")
	assert_true(crop_box.position.y > face_box.position.y, "the crop caps the head above the eyes")
	assert_true(crop_box.size.x > 0.2 and crop_box.size.x < 0.42, "the crop covers the crown")
	assert_true(absf(crop_box.size.x - crop_box.size.z) < 0.08, "the crop follows the pentagon, not a flat bar")
	assert_true(bun_box.size.z > crop_box.size.z, "the bun adds the back of the head")
	var fringe := _roman().hair_style(2)
	assert_false(String(crop.resource_name).begins_with("fallback"), "the crop is the exported mesh")
	assert_false(String(bun.resource_name).begins_with("fallback"), "the bun is the exported mesh")
	assert_false(String(fringe.resource_name).begins_with("fallback"), "the fringe is the exported mesh")
	var crop_tris := _mesh_tris(crop)
	var bun_tris := _mesh_tris(bun)
	var fringe_tris := _mesh_tris(fringe)
	assert_true(crop_tris > 20 and bun_tris > crop_tris and fringe_tris > crop_tris, "the bun and the fringe add to the cap (%d, %d, %d)" % [crop_tris, bun_tris, fringe_tris])
	var fringe_box := fringe.get_aabb()
	assert_true(bun_box.size.z > fringe_box.size.z + 0.01, "the bun is a deeper silhouette than the fringe (%.3f, %.3f)" % [bun_box.size.z, fringe_box.size.z])
	## The crowd draws each layer's bare mesh in a MultiMesh, never the node
	## that carried it in the scene, so every layer must already be in the
	## figure's frame. An offset node once sank every head into its tunic and
	## left the eyes, brow and hair floating where the head should be.
	for cheer: bool in [false, true]:
		for slot: String in ["skin", "fabric", "leather"]:
			var drawn := _roman().part(cheer, slot).get_aabb()
			var placed := _points_box(_figure_points(cheer, slot))
			assert_true(drawn.position.is_equal_approx(placed.position) and drawn.size.is_equal_approx(placed.size), "the drawn %s %s layer is where the figure puts it (%s vs %s)" % ["cheer" if cheer else "seated", slot, drawn, placed])
	var top := -1.0
	for point: Vector3 in _figure_points(false, "skin"):
		top = maxf(top, point.y)
	assert_true(top > 1.1, "the skull clears the collar (top %.3f)" % top)
	var skin_drawn := _roman().part(false, "skin").get_aabb()
	var drawn_top := skin_drawn.position.y + skin_drawn.size.y
	## The authored head is 0.38 m, and the marks sit at Wolf's fraction of it.
	var head_height := 0.38
	assert_true(face_box.position.y > drawn_top - head_height and face_box.end.y < drawn_top, "the eyes and brow sit on the drawn head (face %.3f..%.3f, head top %.3f)" % [face_box.position.y, face_box.end.y, drawn_top])
	var face_share := (face_box.position.y - (drawn_top - head_height)) / head_height
	assert_true(face_share > 0.45, "the marks sit in the upper half of the head, not at the mouth (%.2f)" % face_share)
	var reach := 0.0
	var samples := 0
	for point: Vector3 in _figure_points(false, "skin"):
		if point.y < top - 0.25:
			continue
		samples += 1
		reach = maxf(reach, Vector2(point.x, point.z).length())
	assert_true(samples > 8, "the top of the figure is a skull, not one vertex")
	assert_true(reach > 0.12 and reach < 0.22, "that skull is wider than the neck and narrower than the shoulders (%.3f)" % reach)
	var face_mesh := _roman().face()
	assert_false(String(face_mesh.resource_name).begins_with("fallback"), "the face is the exported mesh")
	var hair_top := crop.get_aabb().position.y + crop.get_aabb().size.y
	assert_true(hair_top > top - 0.15, "the crop sits on the skull (hair %.3f, skull %.3f)" % [hair_top, top])


func test_a_living_fall_follows_root_at_until_the_basin() -> void:
	var exit := Vector3(8.3, 0.0, 0.2)
	var velocity := Vector3(1.5, 0.0, 0.0)
	var request := FallPresentationRequest.create(0, exit, velocity, 3)
	var early := 0.4
	assert_true(RingOutWater.shown(request, early, false, WATER_FIXTURE).is_equal_approx(request.root_at(early)), "before the water the drawing is the ballistic root")
	var entry := RingOutWater.entry_time(request, WATER_FIXTURE)
	var at_entry := request.root_at(entry)
	assert_true(RingOutWater.shown(request, entry, true, WATER_FIXTURE).is_equal_approx(at_entry), "at the water the drawing still is the ballistic root")
	var drifted := RingOutWater.shown(request, entry + 0.05, true, WATER_FIXTURE)
	assert_true(absf(drifted.x - at_entry.x) > 0.01, "horizontal speed carries on instead of stopping in one frame")
	assert_true(drifted.distance_to(at_entry) < 1.0, "the ease does not teleport the body")
	var deep := request.root_at(entry + 1.0)
	var floating := RingOutWater.shown(request, entry + 1.0, true, WATER_FIXTURE)
	assert_true(deep.y < floating.y, "the root keeps falling after the drawing has eased")
	assert_near(request.root_at(0.4).y, -0.5 * FallPresentationRequest.GRAVITY * 0.16, 1e-4, "root_at itself is unchanged")
	var bobbed := RingOutWater.shown(request, entry + 0.4, false, WATER_FIXTURE)
	var still := RingOutWater.shown(request, entry + 0.4, true, WATER_FIXTURE)
	assert_false(is_equal_approx(bobbed.y, still.y), "reduced motion drops the bob")
	assert_eq(RiposteTheme.WORLD_FLOOR, Color("8a7f6c"), "the combat floor color is unchanged")


func test_a_cheer_does_not_allocate_and_a_finish_moves_more_seats() -> void:
	var stage := CrowdStage.create(_roman(), 5)
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
	var stage := CrowdStage.create(_roman(), 9)
	stage.advance(1.0, null, false)
	for index: int in stage.section_count():
		assert_false(stage.section_hidden(index), "section %d stays drawn" % index)
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
	var shape := (arena.presentation_ground().get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D
	var layout := ArenaSection.load_layout()
	var corners := ArenaSurfaceState.corner_radius(ArenaSurfaceState.face_distance(layout.wall_inner), layout.bay_count)
	var reached := 0.0
	for point: Vector3 in shape.points:
		reached = maxf(reached, Vector2(point.x, point.z).length())
	assert_near(reached, corners, 1e-3, "a dropped sword lands on the sand outline")
	assert_true(reached > rules.platform_radius, "that outline is not the combat radius")
	var missing := _roman().part(false, "absent")
	assert_eq(missing.resource_name, "fallback.seated.absent", "a missing part uses the named fallback")
	var text := FileAccess.get_file_as_string("res://content/characters/wolf.character.json")
	assert_true(text.contains("\"skin\""), "fixture: Wolf's palette is in the file")
	assert_true(text.contains("0.87") and text.contains("0.71") and text.contains("0.6"), "Wolf's palette.skin is unchanged")
	var parsed: Variant = JSON.parse_string(text)
	var swatches: Dictionary = (parsed as Dictionary)["skin_swatches"]
	var crowd_skin := _roman().skin
	assert_eq(crowd_skin.size(), swatches.size(), "the crowd uses every authored swatch")
	for index: int in crowd_skin.size():
		var rgb: Array = swatches["skin_%02d" % (index + 1)]
		assert_near(crowd_skin[index].r, float(rgb[0]), 0.002, "skin_%02d red matches the file" % (index + 1))
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


## The landmark constant is the hypothesis. The imported vertices, with the
## glTF node's transform and then the seat pose, are the check.
func test_the_knee_meets_the_lip_and_the_figure_has_limbs() -> void:
	var layout := ArenaSection.load_layout()
	var below := layout.wall_height
	var skin := _figure_points(false, "skin")
	var leather := _figure_points(false, "leather")
	assert_true(skin.size() > 20, "seated skin imported with vertices")
	assert_true(leather.size() > 8, "seated leather imported with vertices")
	var opposite := int(float(layout.bay_count) * 0.5)
	for tier: int in layout.tier_count():
		for bay: int in [0, opposite]:
			var pose := layout.pose_for(tier, bay, 0)
			var knee_z := 0.0
			var knee_y := 0.0
			var found_knee := false
			for point: Vector3 in skin:
				if point.y < 0.32 or point.y > 0.55:
					continue
				if not found_knee or point.z < knee_z:
					knee_z = point.z
					knee_y = point.y
					found_knee = true
			assert_true(found_knee, "tier %d has a knee band" % tier)
			var knee := pose * Vector3(0.0, knee_y, knee_z)
			var knee_radius := Vector2(knee.x, knee.z).length()
			assert_true(absf(knee_radius - layout.tier_inner[tier]) < 0.12, "tier %d bay %d knee is at the lip (%.3f, lip %.3f)" % [tier, bay, knee_radius, layout.tier_inner[tier]])
			var thigh_low := 100.0
			var thigh_on_tread := false
			for point: Vector3 in skin:
				if point.y < 0.40 or point.z < -0.15:
					continue
				var world := pose * point
				thigh_low = minf(thigh_low, world.y)
				if Vector2(world.x, world.z).length() > layout.tier_inner[tier] - 0.02:
					thigh_on_tread = true
			assert_true(thigh_on_tread, "tier %d bay %d thigh stays on the tread" % [tier, bay])
			assert_true(thigh_low > layout.tier_height[tier] - 0.12, "tier %d thigh is not sunk through the stone (%.3f)" % [tier, thigh_low])
			var shin_clear := false
			for point: Vector3 in skin:
				if point.y > 0.30 or point.z > -0.28:
					continue
				var world := pose * point
				if Vector2(world.x, world.z).length() < layout.tier_inner[tier] - 0.02:
					shin_clear = true
			assert_true(shin_clear, "tier %d bay %d shin is in front of the riser" % [tier, bay])
			var sole := 100.0
			var boot_front := false
			for point: Vector3 in leather:
				if point.y > 0.22:
					continue
				var world := pose * point
				sole = minf(sole, world.y)
				if Vector2(world.x, world.z).length() < layout.tier_inner[tier] - 0.02:
					boot_front = true
			assert_true(boot_front, "tier %d bay %d boot hangs in front of the riser" % [tier, bay])
			assert_true(sole > below + 0.02, "tier %d boot clears the surface below (%.3f)" % [tier, sole])
			assert_true(sole < below + 0.40, "tier %d boot does not float (%.3f)" % [tier, sole])
		below = layout.tier_height[tier]
	for cheer: bool in [false, true]:
		for slot: String in ["skin", "fabric", "leather"]:
			var mesh := _roman().part(cheer, slot)
			assert_false(mesh.resource_name.begins_with("fallback"), "%s %s is the exported mesh" % ["cheer" if cheer else "seated", slot])
	var cheer_skin := _figure_points(true, "skin")
	var hand := false
	var elbow := false
	for point: Vector3 in cheer_skin:
		if point.y > 1.15:
			hand = true
		if point.y > 0.95 and point.y < 1.20:
			elbow = true
	assert_true(hand and elbow, "the cheer arms have an elbow and a raised hand")


func _points_box(points: PackedVector3Array) -> AABB:
	var box := AABB(points[0], Vector3.ZERO)
	for point: Vector3 in points:
		box = box.expand(point)
	return box


func _figure_points(cheer: bool, slot: String) -> PackedVector3Array:
	var packed := _roman().pose_scene(cheer)
	var points := PackedVector3Array()
	if packed == null:
		return points
	var root := packed.instantiate()
	_collect_slot(root, root, slot, points)
	root.free()
	return points


func _collect_slot(root: Node, node: Node, slot: String, points: PackedVector3Array) -> void:
	if node is MeshInstance3D and String(node.name).to_lower() == slot:
		var mesh_node := node as MeshInstance3D
		var chain := _to_figure_root(root, mesh_node)
		var mesh := mesh_node.mesh
		for surface: int in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in verts:
				points.append(chain * vertex)
		return
	for child: Node in node.get_children():
		_collect_slot(root, child, slot, points)


func _to_figure_root(root: Node, node: Node3D) -> Transform3D:
	var chain := Transform3D.IDENTITY
	var cursor: Node = node
	while cursor is Node3D and cursor != root:
		chain = (cursor as Node3D).transform * chain
		cursor = cursor.get_parent()
	return chain


func test_the_sand_stays_one_flat_colour() -> void:
	var layout := ArenaSection.load_layout()
	var sand := ArenaSurfaceState.create(8.27, layout)
	var top := sand.get_node("Top") as MeshInstance3D
	var ink := top.material_override as StandardMaterial3D
	assert_eq(ink.albedo_color, RiposteTheme.SAND, "the floor is one sand colour")
	assert_false(ink.vertex_color_use_as_albedo, "a step does not retint the floor")
	var highest := -1.0
	var lowest := 1.0
	for vertex: Vector3 in top.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		highest = maxf(highest, vertex.y)
		lowest = minf(lowest, vertex.y)
	assert_near(highest, 0.0, 1e-4, "the sand stays on the ground")
	assert_near(lowest, 0.0, 1e-4, "the sand does not open a hole")
	sand.free()


## The inner course has to stand just outside the door, and the doorway
## itself has to be empty. A vertex on the outer wall is too far away to pass.
func test_the_wall_continues_beside_both_doors() -> void:
	var layout := ArenaSection.load_layout()
	var inner := layout.wall_inner + ArenaSurfaceState.STONE_FACE_OUTSET
	var half := layout.gate_width * 0.5
	var face := inner + 0.05
	var side := half + 0.08
	var packed := load(ArenaScaffold.BOWL_SCENE) as PackedScene
	var bowl := packed.instantiate()
	var stone := _inner_course(bowl, inner + 0.45, layout.gate_height)
	var sides: Array[float] = [-1.0, 1.0]
	for gate_sign: float in sides:
		var along: float = gate_sign * face
		for lateral: float in sides:
			var jamb := Vector3(lateral * side, 0.8, -along)
			var nearest := _nearest_point(stone, jamb)
			assert_true(nearest < 0.20, "inner course beside the door at (%.2f, %.2f), nearest %.2f" % [jamb.x, jamb.z, nearest])
	var buried_recess := 0
	for point: Vector3 in stone:
		if absf(point.x) >= half - 0.05:
			continue
		if absf(point.z) > inner + 0.03 and absf(point.z) < inner + layout.gate_depth - 0.03:
			buried_recess += 1
	assert_eq(buried_recess, 0, "no stone inside the door recess")
	var found_pos := false
	var found_neg := false
	for instance: MeshInstance3D in _meshes_under(bowl):
		if _is_gate(instance):
			var box := _world_bounds(instance).grow(-0.04)
			var buried := false
			for point: Vector3 in stone:
				if _strictly_inside(box, point):
					buried = true
			assert_false(buried, "%s does not contain stone" % instance.name)
			var reach := _innermost_radius(instance)
			assert_true(reach > layout.expected_disc_radius + 0.02, "%s stays outside the combat disc (%.2f)" % [instance.name, reach])
			continue
		var xform := _chain(instance)
		var mesh := instance.mesh
		if mesh == null:
			continue
		for surface: int in mesh.get_surface_count():
			var arrays: Array = mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var tri := 0
			while tri + 2 < indices.size():
				var i0 := indices[tri]
				var i1 := indices[tri + 1]
				var i2 := indices[tri + 2]
				var a := xform * vertices[i0]
				var b := xform * vertices[i1]
				var c := xform * vertices[i2]
				var center := (a + b + c) / 3.0
				tri += 3
				if absf(absf(center.x) - half) > 0.03:
					continue
				if absf(center.z) < inner - 0.05 or absf(center.z) > inner + layout.gate_depth + 0.08:
					continue
				if center.y < 0.3 or center.y > 1.3:
					continue
				var normal := (b - a).cross(c - a)
				if not normals.is_empty():
					normal = xform.basis * (normals[i0] + normals[i1] + normals[i2])
				normal = normal.normalized()
				if absf(normal.x) < 0.85:
					continue
				if center.x * normal.x < -0.4:
					if center.x > 0.0:
						found_pos = true
					else:
						found_neg = true
	assert_true(found_pos and found_neg, "both jambs have a face into the opening")
	assert_true(_find(bowl, "GateNorth") != null, "the north door stays")
	assert_true(_find(bowl, "GateSouth") != null, "the south door stays")
	var bodies := 0
	for child: Node in bowl.get_children():
		if child is StaticBody3D or child is CharacterBody3D:
			bodies += 1
	assert_eq(bodies, 0, "the wall still has no collider")
	bowl.free()


func test_a_walk_leaves_the_sand_flat() -> void:
	var rules := StandardDuelRules.pit()
	var root := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var camera := DuelCameraRig.new()
	root.add_child(camera)
	camera.configure(RiposteKits.camera_profile())
	var state := DuelSetup.new_state(rules, 1)
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var opening := SnapshotProjector.project(state, rules)
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), camera, rules.platform_radius, rules.edge_warning_inset, opening)
	root.add_child(presenter)
	presenter.push(opening, [])
	presenter.render(1.0, 0.05)
	for _step in 4:
		state.fighter(0).x += 0.45
		presenter.push(SnapshotProjector.project(state, rules), [])
		presenter.render(1.0, 0.05)
	state.fighter(0).facing += 0.8
	presenter.push(SnapshotProjector.project(state, rules), [])
	presenter.render(1.0, 0.05)
	var top := ((presenter.get_node("Arena") as ArenaScaffold).sand().get_node("Top")) as MeshInstance3D
	var ink := top.material_override as StandardMaterial3D
	assert_eq(ink.albedo_color, RiposteTheme.SAND, "a walk does not retint the sand")
	for vertex: Vector3 in top.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		assert_near(vertex.y, 0.0, 1e-4, "a walk does not move the sand")
	root.free()


func test_the_gates_stand_behind_the_spawns() -> void:
	var layout := ArenaSection.load_layout()
	var packed := load(ArenaScaffold.BOWL_SCENE) as PackedScene
	var bowl := packed.instantiate()
	var north := _find(bowl, "GateNorth") as Node3D
	var south := _find(bowl, "GateSouth") as Node3D
	assert_true(north != null and south != null, "both gates are in the bowl")
	var north_at := _centroid(north)
	var south_at := _centroid(south)
	var rules := StandardDuelRules.pit()
	var south_spawn := ArenaTransform.to_world(0.0, DuelSide.spawn_y(DuelSide.Id.LIGHT_SOUTH, rules.spawn_offset))
	var north_spawn := ArenaTransform.to_world(0.0, DuelSide.spawn_y(DuelSide.Id.DARK_NORTH, rules.spawn_offset))
	assert_true(absf(north_at.x) < 1.5 and north_at.z < north_spawn.z, "the north gate is beyond the north spawn (z %.2f, spawn %.2f)" % [north_at.z, north_spawn.z])
	assert_true(absf(south_at.x) < 1.5 and south_at.z > south_spawn.z, "the south gate is beyond the south spawn (z %.2f, spawn %.2f)" % [south_at.z, south_spawn.z])
	assert_true(Vector2(north_at.x, north_at.z).length() > layout.expected_disc_radius, "the north gate is outside the sand")
	assert_true(Vector2(south_at.x, south_at.z).length() > layout.expected_disc_radius, "the south gate is outside the sand")
	bowl.free()


func test_the_layout_puts_feet_on_four_treads_and_leaves_the_disc_alone() -> void:
	var rules := StandardDuelRules.create()
	var layout := ArenaSection.load_layout()
	assert_eq(layout.issues().size(), 0, "the shipped layout is valid")
	assert_near(layout.expected_disc_radius, 8.27, 1e-6, "the file records the combat radius")
	assert_true(layout.agrees(rules.platform_radius), "the record matches the rules")
	assert_near(layout.combat_disc(9.0), 9.0, 1e-6, "a disagreement would still use the rules")
	assert_false(layout.agrees(9.0), "9 m does not match the record")
	assert_true(layout.pit, "the shipped bowl is the sand pit")
	assert_near(layout.wall_inner, layout.expected_disc_radius, 1e-4, "the wall starts at the combat radius")
	assert_near(layout.tier_inner[0], layout.wall_outer, 1e-4, "the first seats start where the wall ends")
	assert_true(layout.tier_height[0] > layout.wall_height, "those seats are one level above the wall")
	assert_eq(layout.course_axis, "east_west", "the paving runs east-west")
	assert_near(layout.curb_height, 0.0, 1e-6, "the fighting surface has no raised edge")
	var raised := ArenaSection.load_layout()
	raised.curb_height = 0.09
	assert_true(raised.issues().size() > 0, "a 9 cm lip is not a flush edge")
	assert_near(layout.foot_offset, 0.4, 1e-6, "the origin drops so the seat of the figure meets the tread")
	assert_true(layout.gate_height > layout.wall_height, "the gates rise through the wall")
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
	heights[heights.size() - 1] = heights[0]
	broken.tier_height = heights
	assert_true(broken.issues().size() > 0, "a tread that does not rise fails the check")
	var stage := CrowdStage.create(_roman(), 5)
	var again := CrowdStage.create(_roman(), 5)
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
	assert_eq(sky_mat.sky_horizon_color, RiposteTheme.SKY_HORIZON, "the horizon color is the theme")
	assert_near(sky_mat.sun_angle_max, RiposteTheme.SKY_SUN_ANGLE_MAX, 1e-4, "the sun disc is the theme's small region")
	assert_true(RiposteTheme.SKY_SUN_ANGLE_MAX > 0.0, "the sky keeps a sun disc")
	assert_eq(env.environment.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "the sky does not relight the fighters")
	assert_near(env.environment.ambient_light_energy, RiposteTheme.WORLD_AMBIENT_ENERGY, 1e-4, "the fill energy is the theme")
	var key := arena.get_node("KeyLight") as DirectionalLight3D
	var rim := arena.get_node("RimLight") as DirectionalLight3D
	assert_true(key.shadow_enabled, "the warm key casts the one shadow map")
	assert_eq(key.directional_shadow_mode, DirectionalLight3D.SHADOW_ORTHOGONAL, "in one orthogonal split")
	assert_near(key.directional_shadow_max_distance, ArenaScaffold.KEY_SHADOW_DISTANCE, 1e-4, "over the duel camera's view only")
	assert_false(rim.shadow_enabled, "the rim never casts")
	assert_eq(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"), 1024, "a 1024 map: a 512 one broke the sword's shadow into dots")
	assert_eq(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality"), 0, "hard filtering: the soft filter smears, and shadow_blur does nothing on Compatibility")
	assert_eq(key.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY, "the key draws the one sun")
	assert_eq(rim.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_ONLY, "the rim does not add a second sun")
	assert_true(key.light_energy > rim.light_energy, "the key stays stronger than the cool fill")
	assert_eq(RiposteTheme.SAND, Color("a7a49a"), "the visible disc is the neutral stone-gray sand token")
	assert_eq(RiposteTheme.WORLD_FLOOR, Color("8a7f6c"), "the clothing token stays the mid stone")
	var paving := arena.get_node_or_null("SandSurface")
	var bowl := arena.get_node_or_null("Bowl")
	assert_true(paving != null, "the sand disc is on the scaffold")
	assert_true(bowl != null, "the bowl is instanced")
	var top := _find(arena, "PlatformTop") as Node3D
	assert_true(top != null, "the rollback disc is still in the authored scene")
	assert_false(top.visible, "the plug is hidden while the sand disc is shown")
	assert_false(ArenaScaffold.is_stand_in("PlatformTop"), "the disc is not an ornamental stand-in")
	assert_true(ArenaScaffold.is_replaced_disc("PlatformTop"), "the disc is the surface the floor replaces")
	assert_true(arena.get_node_or_null("BoundaryRing") == null, "the gold ring is not drawn")
	assert_true(arena.get_node_or_null("EdgeStrip") == null, "the edge strip is not drawn")
	assert_true(arena.get_node_or_null("HomeLight") != null, "the light home mark stays")
	assert_true(arena.get_node_or_null("HomeDark") != null, "the dark home mark stays")
	assert_eq(_casting(bowl, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF), 0, "the wall casts into the key's map")
	var crowd := arena.crowd()
	assert_true(crowd != null, "fixture: the pit seats a crowd")
	assert_eq(_casting(crowd, GeometryInstance3D.SHADOW_CASTING_SETTING_ON), 0, "the crowd never casts")
	_assert_sand(paving, bowl, rules.platform_radius, layout)
	_assert_bowl(bowl, layout)
	arena.free()


func test_the_end_is_a_deck_in_the_void() -> void:
	var rules := StandardDuelRules.create()
	rules.arena_id = ContentIds.ARENA_END
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	assert_eq(kits.arena.id, ContentIds.ARENA_END, "the deck kit resolves")
	assert_true(kits.arena.scene != null, "and it has a scene")
	assert_true(kits.arena.audio_cues.has(PresentationKit.CUE_MUSIC), "music still plays")
	assert_true(kits.arena.stream_for(PresentationKit.CUE_ROUND) != null, "the round sting still plays")
	assert_false(kits.arena.audio_cues.has(PresentationKit.CUE_CROWD_BED), "no crowd bed")
	assert_false(kits.arena.audio_cues.has(PresentationKit.CUE_CROWD_CHEER), "no cheer")
	var profile := ArenaScaffold.profile_of(kits.arena)
	assert_eq(profile.problem(), "", "the deck profile is complete")
	assert_eq(profile.ground, StagePresentationProfile.Ground.DECK, "the kit asks for a deck, not a pit")
	assert_eq(profile.backdrop, StagePresentationProfile.Backdrop.VOID, "in the void")
	var deck := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, rules.spawn_offset, 4)
	assert_true(deck.crowd() == null, "no crowd nodes")
	assert_true(deck.sand() == null, "no sand")
	assert_true(deck.get_node_or_null("Bowl") == null, "no bowl")
	assert_true(deck.get_node_or_null("Deck") != null, "the deck is in the match")
	assert_true(deck.get_node_or_null("HomeLight") == null and deck.get_node_or_null("HomeDark") == null, "no home marks on the uninterrupted deck")
	var env := deck.get_node("Environment") as WorldEnvironment
	var sky_mat := env.environment.sky.sky_material as ProceduralSkyMaterial
	assert_eq(sky_mat.sky_top_color, RiposteTheme.END_SKY, "void above")
	assert_eq(sky_mat.ground_bottom_color, RiposteTheme.END_VOID_DEEP, "near-black under the deck")
	assert_eq(sky_mat.ground_horizon_color, RiposteTheme.END_VOID_HORIZON, "a faint lift toward the horizon")
	assert_true(RiposteTheme.END_VOID_HORIZON.get_luminance() > RiposteTheme.END_VOID_DEEP.get_luminance() + 0.05, "the lift is a gradient, not one colour")
	assert_near(sky_mat.sun_angle_max, 0.0, 1e-4, "no sun disc")
	var key := deck.get_node("KeyLight") as DirectionalLight3D
	var rim := deck.get_node("RimLight") as DirectionalLight3D
	assert_eq(key.sky_mode, DirectionalLight3D.SKY_MODE_LIGHT_ONLY, "the key does not draw a sun on the void")
	assert_true(key.shadow_enabled, "the key casts onto the deck")
	assert_false(rim.shadow_enabled, "the rim never casts")
	var stage := deck.get_node("Deck")
	assert_eq(_casting(stage, GeometryInstance3D.SHADOW_CASTING_SETTING_ON), 0, "the deck only receives")
	var top := _find(deck, "Top") as MeshInstance3D
	assert_true(top != null and top.mesh != null, "the deck top is named")
	assert_true(_find(deck, "Edge") != null, "the lip is its own part")
	assert_true(_find(deck, "Underside") != null, "the underside is its own part")
	assert_true(_find(deck, "Orb") != null, "the orb is its own part")
	_assert_deck_boundaries(deck, profile, rules.platform_radius)
	assert_true(RiposteKits.duelist_victory().sting != null, "the victory sting still loads")
	deck.free()


## Three boundaries, on purpose. Combat is the support circle. The visible
## deck covers it everywhere (no legal ground without deck) and its corners
## overhang it. The sword floor is the visible outline, not the circle.
func _assert_deck_boundaries(deck: ArenaScaffold, profile: StagePresentationProfile, support: float) -> void:
	var outline := profile.deck_outline()
	assert_eq(outline, deck.ground_outline(), "the scaffold's ground is the profile outline")
	var flat := INF
	var corner := 0.0
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
		flat = minf(flat, absf(normal.dot(a)))
		corner = maxf(corner, a.length())
	assert_true(flat >= support, "every flat of the visible deck is on or past the support circle (%.3f m)" % flat)
	assert_near(corner, profile.deck_flat / cos(PI / 8.0), 1e-3, "the corners are the octagon's, not clipped")
	assert_true(corner - support > 0.6, "and overhang the support circle by %.2f m, so a corner fall needs the ledge" % (corner - support))
	var top := _find(deck, "Top") as MeshInstance3D
	var top_flat := 0.0
	var highest := -10.0
	var meshes: Array[MeshInstance3D] = [top, _find(deck, "Edge") as MeshInstance3D]
	var reach := 0.0
	for instance: MeshInstance3D in meshes:
		var xform := _chain(instance)
		for surface: int in instance.mesh.get_surface_count():
			for vertex: Vector3 in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = xform * vertex
				reach = maxf(reach, Vector2(point.x, point.z).length())
				if instance == top:
					top_flat = maxf(top_flat, maxf(absf(point.x), absf(point.z)))
					highest = maxf(highest, point.y)
	assert_near(top_flat, support, 0.02, "the imported top's flats are the support radius")
	assert_near(highest, 0.0, 0.02, "the fighting surface is at y = 0")
	assert_true(_inside_all(outline, meshes, 0.01), "no drawn deck or lip lies outside the outline")
	assert_near(reach, corner, 0.02, "and the outline reaches the drawn corners")
	var ground := deck.presentation_ground()
	var shape := (ground.get_child(0) as CollisionShape3D).shape as ConvexPolygonShape3D
	assert_true(shape != null, "the sword floor is a polygon")
	var floor_reach := 0.0
	for point: Vector3 in shape.points:
		floor_reach = maxf(floor_reach, Vector2(point.x, point.z).length())
	assert_near(floor_reach, corner, 1e-3, "the sword floor reaches the drawn corners, so a dropped sword has deck under it")


func _inside(outline: PackedVector2Array, plan: Vector2, slack: float) -> bool:
	var centre := Vector2.ZERO
	for point: Vector2 in outline:
		centre += point
	centre /= float(outline.size())
	for i in outline.size():
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
		if normal.dot(a - centre) < 0.0:
			normal = -normal
		if normal.dot(plan - a) > slack:
			return false
	return true


func _inside_all(outline: PackedVector2Array, meshes: Array[MeshInstance3D], slack: float) -> bool:
	for instance: MeshInstance3D in meshes:
		var xform := _chain(instance)
		for surface: int in instance.mesh.get_surface_count():
			for vertex: Vector3 in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = xform * vertex
				if not _inside(outline, Vector2(point.x, point.z), slack):
					return false
	return true


func _casting(root: Node, setting: GeometryInstance3D.ShadowCastingSetting) -> int:
	var count := 1 if root is GeometryInstance3D and (root as GeometryInstance3D).cast_shadow == setting else 0
	for child: Node in root.get_children():
		count += _casting(child, setting)
	return count


## A ring-out at a corner crosses the support circle while the drawn octagon
## still extends past it. The drawing slides on the drawn top until it clears
## the outline, then drops: never below the top while over visible deck.
func test_a_corner_ring_out_leaves_the_drawn_deck_before_it_drops() -> void:
	var rules := StandardDuelRules.create()
	rules.arena_id = ContentIds.ARENA_END
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var outline := ArenaScaffold.profile_of(kits.arena).deck_outline()
	assert_true(outline.size() == 8, "fixture: the deck outline is the octagon")
	var corner_dir := outline[0].normalized()
	var speed := 1.5
	var corner := FallPresentationRequest.create(0, Vector3(corner_dir.x, 0.0, corner_dir.y) * rules.platform_radius, Vector3(corner_dir.x, 0.0, corner_dir.y) * speed, 1)
	assert_near(corner.root_at(0.2).y, -0.5 * FallPresentationRequest.GRAVITY * 0.04, 1e-6, "fixture: without a ledge the root drops at once")
	corner.leave_ground(outline)
	var expected := (outline[0].length() - rules.platform_radius) / speed
	assert_near(corner.ledge_seconds, expected, 1e-3, "the slide lasts until the drawn corner (%.2f s)" % expected)
	var t := 0.0
	var over_deck := 0
	while t < 1.2:
		var at := corner.root_at(t)
		if _inside(outline, Vector2(at.x, at.z), -1.0e-4):
			over_deck += 1
			assert_near(at.y, 0.0, 1e-6, "%.2f s: over visible deck the root is on the top" % t)
		t += 1.0 / 60.0
	assert_true(over_deck > 10, "fixture: the root spends frames over the corner (%d)" % over_deck)
	assert_true(corner.root_at(expected + 0.3).y < -0.3, "past the corner it falls")
	assert_true(corner.velocity_at(expected * 0.5).y == 0.0, "and does not move down while it slides")
	var flat := FallPresentationRequest.create(0, Vector3(rules.platform_radius, 0.0, 0.0), Vector3(speed, 0.0, 0.0), 2)
	flat.leave_ground(outline)
	assert_true(flat.ledge_seconds < 0.05, "across a flat only the inlay is overhang (%.3f s)" % flat.ledge_seconds)
	var bare := FallPresentationRequest.create(0, Vector3(rules.platform_radius, 0.0, 0.0), Vector3(speed, 0.0, 0.0), 3)
	bare.leave_ground(PackedVector2Array())
	assert_eq(bare.ledge_seconds, 0.0, "no outline, no ledge")
	var beyond := FallPresentationRequest.create(0, Vector3(9.5, 0.0, 0.0), Vector3(speed, 0.0, 0.0), 4)
	beyond.leave_ground(outline)
	assert_eq(beyond.ledge_seconds, 0.0, "a crossing already past the deck drops at once")
	var still := FallPresentationRequest.create(0, Vector3(rules.platform_radius, 0.0, 0.0), Vector3.ZERO, 5)
	still.leave_ground(outline)
	assert_true(still.ledge_seconds <= FallPresentationRequest.LEDGE_LIMIT, "a body with no exit speed is not held on decoration forever")


func _on_tread(origin: Vector3, layout: ArenaSection) -> bool:
	var radius := Vector2(origin.x, origin.z).length()
	for tier: int in layout.tier_count():
		if absf(origin.y + layout.foot_offset - layout.tier_height[tier]) > 0.001:
			continue
		if radius > layout.tier_inner[tier] - 0.05 and radius < layout.tier_outer[tier] + 0.05:
			return true
	return false


func _assert_sand(paving: Node, bowl: Node, platform_radius: float, layout: ArenaSection) -> void:
	assert_eq(paving.get_child_count(), 1, "the floor is one mesh")
	assert_true(paving.get_node_or_null("Rim") == null, "the wooden rim is gone")
	assert_true(paving.get_node_or_null("Side") == null, "the wooden side is gone")
	var top := paving.get_node("Top") as MeshInstance3D
	var reached := 0.0
	var highest := -1.0
	var lowest := 1.0
	for vertex: Vector3 in top.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		reached = maxf(reached, Vector2(vertex.x, vertex.z).length())
		highest = maxf(highest, vertex.y)
		lowest = minf(lowest, vertex.y)
	assert_near(highest, 0.0, 1e-4, "the sand is on the ground plane")
	assert_near(lowest, 0.0, 1e-4, "the sand has no vertical side")
	var apothem := ArenaSurfaceState.face_distance(layout.wall_inner)
	var vertex_radius := ArenaSurfaceState.corner_radius(apothem, layout.bay_count)
	assert_near(reached, vertex_radius, 1e-2, "the corners tuck under the courses")
	assert_true(reached > platform_radius, "the floor passes the combat radius")
	var vertices: PackedVector3Array = top.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for bay: int in layout.bay_count:
		var angle := layout.angular_zero + TAU * float(bay) / float(layout.bay_count)
		var normal := Vector2(cos(angle), sin(angle))
		var support := 0.0
		for vertex: Vector3 in vertices:
			support = maxf(support, Vector2(vertex.x, vertex.z).dot(normal))
		assert_near(support, apothem, 1e-2, "bay %d face sits on the wall line" % bay)
	var sand := top.material_override as StandardMaterial3D
	assert_eq(sand.albedo_color, RiposteTheme.SAND, "the floor is sand")
	var stone := _innermost_above(bowl, 0.05)
	assert_true(apothem + 0.02 >= stone, "the sand meets the inner stone (face %.3f, stone %.3f)" % [apothem, stone])
	assert_true(reached < layout.wall_outer, "the sand stays inside the wall")
	assert_eq(_bodies(paving), 0, "the sand disc adds no collider")


func _innermost_above(bowl: Node, above_y: float) -> float:
	var nearest := 1000.0
	for instance: MeshInstance3D in _meshes_under(bowl):
		var mesh := instance.mesh
		if mesh == null:
			continue
		var xform := _chain(instance)
		for surface: int in mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			for vertex: Vector3 in vertices:
				var point := xform * vertex
				if point.y <= above_y:
					continue
				nearest = minf(nearest, Vector2(point.x, point.z).length())
	return nearest


func _assert_bowl(bowl: Node, layout: ArenaSection) -> void:
	if layout.pit:
		_assert_pit_bowl(bowl, layout)
		return
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


func _assert_pit_bowl(bowl: Node, layout: ArenaSection) -> void:
	var disc := layout.expected_disc_radius
	var top := layout.tier_height[layout.tier_count() - 1]
	var north := false
	var south := false
	for instance: MeshInstance3D in _meshes_under(bowl):
		if String(instance.name) == "GateNorth":
			north = true
		if String(instance.name) == "GateSouth":
			south = true
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
				assert_true(radius > disc + 0.02 or point.y <= 0.02, "the sand stays clear")
				assert_true(point.y <= top + 0.08, "nothing stands above the seats")
		_assert_bowl_material(instance)
	assert_true(north and south, "a wooden gate stands behind each spawn")


func _assert_bowl_material(instance: MeshInstance3D) -> void:
	var material: Material = instance.material_override
	if material == null and instance.mesh != null and instance.mesh.get_surface_count() > 0:
		material = instance.mesh.surface_get_material(0)
	assert_true(material is StandardMaterial3D, "%s has a standard material" % instance.name)
	var ink := material as StandardMaterial3D
	assert_eq(ink.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED, "%s is opaque" % instance.name)
	assert_eq(ink.cull_mode, BaseMaterial3D.CULL_DISABLED, "%s draws both sides" % instance.name)


func _mesh_tris(mesh: Mesh) -> int:
	var count := 0
	for surface: int in mesh.get_surface_count():
		var indices: PackedInt32Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_INDEX]
		count += int(float(indices.size()) / 3.0)
	return count


func _inner_course(bowl: Node, band: float, gate_height: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	for instance: MeshInstance3D in _meshes_under(bowl):
		if _is_gate(instance) or instance.mesh == null:
			continue
		var xform := _chain(instance)
		for surface: int in instance.mesh.get_surface_count():
			for vertex: Vector3 in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var point := xform * vertex
				if Vector2(point.x, point.z).length() > band:
					continue
				if point.y <= 0.15 or point.y >= gate_height - 0.15:
					continue
				points.append(point)
	return points


func _nearest_point(points: PackedVector3Array, at: Vector3) -> float:
	var nearest := 1000.0
	for point: Vector3 in points:
		nearest = minf(nearest, point.distance_to(at))
	return nearest


func _is_gate(node: Node) -> bool:
	var cursor: Node = node
	while cursor != null:
		var node_name := String(cursor.name)
		if node_name == "GateNorth" or node_name == "GateSouth":
			return true
		cursor = cursor.get_parent()
	return false


func _world_bounds(instance: MeshInstance3D) -> AABB:
	var box := AABB()
	var started := false
	var xform := _chain(instance)
	for surface: int in instance.mesh.get_surface_count():
		for vertex: Vector3 in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point := xform * vertex
			if not started:
				box = AABB(point, Vector3.ZERO)
				started = true
			else:
				box = box.expand(point)
	return box


func _strictly_inside(box: AABB, point: Vector3) -> bool:
	var lo := box.position
	var hi := box.position + box.size
	return point.x > lo.x and point.x < hi.x and point.y > lo.y and point.y < hi.y and point.z > lo.z and point.z < hi.z


func _innermost_radius(instance: MeshInstance3D) -> float:
	var nearest := 1000.0
	var xform := _chain(instance)
	for surface: int in instance.mesh.get_surface_count():
		for vertex: Vector3 in instance.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
			var point := xform * vertex
			nearest = minf(nearest, Vector2(point.x, point.z).length())
	return nearest


func _meshes_under(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_meshes_under(child))
	return found


func _centroid(instance: MeshInstance3D) -> Vector3:
	var mesh := instance.mesh
	var xform := _chain(instance)
	var sum := Vector3.ZERO
	var count := 0
	for surface: int in mesh.get_surface_count():
		var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
		for vertex: Vector3 in vertices:
			sum += xform * vertex
			count += 1
	return sum / float(maxi(count, 1))


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
