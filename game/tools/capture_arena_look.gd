extends SceneTree

## Compatibility look at the floor and one arcade slice, from both opening cameras.
## Not a test. Writes PNGs under .reports/arena_look.
##
##   godot --path game --rendering-method gl_compatibility -s res://tools/capture_arena_look.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://../.reports/arena_look")
	DirAccess.make_dir_recursive_absolute(out)
	var full := false
	var inspect := false
	var sand_trail := false
	var doors := false
	var pair := false
	var steps := false
	var bench := false
	var hair := false
	var end := false
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--full":
			full = true
		elif argument == "--inspect":
			inspect = true
		elif argument == "--sand":
			sand_trail = true
		elif argument == "--doors":
			doors = true
		elif argument == "--pair":
			pair = true
		elif argument == "--steps":
			steps = true
		elif argument == "--bench":
			bench = true
		elif argument == "--hair":
			hair = true
		elif argument == "--end":
			end = true
	if doors or bench:
		full = true
	var viewport := SubViewport.new()
	viewport.name = "Look"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var world := Node3D.new()
	world.name = "World"
	viewport.add_child(world)
	var rules := StandardDuelRules.create()
	if end:
		rules.arena_id = ContentIds.ARENA_END
	var skins: Array[StringName] = [&"", &""]
	if pair:
		skins[1] = RiposteKits.SKIN_DUELIST_TRAINING
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules, skins)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	var arena := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, rules.spawn_offset, 4)
	world.add_child(arena)
	_fighters(world, rules, kits)
	if not full and not end:
		var layout := ArenaSection.load_layout()
		var bowl := arena.get_node_or_null("Bowl")
		if bowl is Node3D:
			(bowl as Node3D).visible = false
		if arena.crowd() != null:
			arena.crowd().visible = false
		var roman := ArenaScaffold.profile_of(kits.arena).crowd
		if layout.issues().is_empty() and roman != null:
			var watched := PackedInt32Array([layout.bay_near(PI * 0.5), layout.bay_near(-PI * 0.5)])
			var skin := roman.part(false, "skin")
			var cloth := roman.part(false, "fabric")
			var leather := roman.part(false, "leather")
			for bay_index: int in watched:
				for tier: int in layout.tier_count():
					for slot: int in layout.slots_in_bay(tier):
						var pose := layout.pose_for(tier, bay_index, slot)
						_figure(arena, skin, pose)
						_figure(arena, cloth, pose)
						_figure(arena, leather, pose)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var options := PresentationOptions.new()
	var shots: Array[Dictionary] = [
		{"name": "light_near", "side": DuelSide.Id.LIGHT_SOUTH, "gap": 0.5},
		{"name": "light_far", "side": DuelSide.Id.LIGHT_SOUTH, "gap": 6.4},
		{"name": "dark_near", "side": DuelSide.Id.DARK_NORTH, "gap": 0.5},
		{"name": "dark_far", "side": DuelSide.Id.DARK_NORTH, "gap": 6.4},
	]
	var sampled := false
	var prefix := "end_" if end else ("pair_" if pair else ("full_" if full else ""))
	for shot: Dictionary in shots:
		var gap := float(shot["gap"])
		rig.look_from(shot["side"] as DuelSide.Id)
		rig.frame(Vector3(0.0, 0.0, -gap * 0.5), Vector3(0.0, 0.0, gap * 0.5), 0.0, options, true)
		rig.camera().current = true
		if full and not sampled:
			sampled = true
			await _frame_sample()
		await process_frame
		await process_frame
		_save(viewport, out, "%s%s" % [prefix, String(shot["name"])])
	if end:
		## Past the rim, so the taper and the orb can be seen. Not the match camera.
		var under := Camera3D.new()
		under.fov = RiposteKits.camera_profile().fov_degrees
		world.add_child(under)
		under.current = true
		under.position = Vector3(14.0, 0.6, 0.0)
		under.look_at(Vector3(0.0, -1.6, 0.0))
		await process_frame
		await process_frame
		_save(viewport, out, "end_underside")
		under.current = false
		rig.camera().current = true
	_grayscale(arena, true)
	await process_frame
	await process_frame
	_save(viewport, out, "%sgray" % prefix)
	if sand_trail:
		_grayscale(arena, false)
		rig.look_from(DuelSide.Id.LIGHT_SOUTH)
		rig.frame(Vector3(0.0, 0.0, -0.25), Vector3(0.0, 0.0, 0.25), 0.0, options, true)
		rig.camera().current = true
		await process_frame
		await process_frame
		_save(viewport, out, "sand_flat")
	if doors:
		await _door_shots(viewport, world, arena, out)
	if steps:
		await _step_shots(viewport, world, arena, out)
	if bench:
		await _bench(viewport, world, arena)
	if inspect:
		await _inspect_figures(viewport, world, arena, out)
	if hair:
		_grayscale(arena, false)
		await _hair_views(viewport, world, out)
	print("RIPOSTE_LOOK_DIR", out)
	quit()


## Gameplay fov and 48° pitch, aimed at one seat from the sand side.
## Closer than the match frame so a limb can be seen. Not a different lens.
func _inspect_figures(viewport: SubViewport, world: Node3D, arena: Node3D, out: String) -> void:
	_grayscale(arena, false)
	var crowd: CrowdStage = arena.crowd()
	if crowd == null:
		return
	crowd.visible = false
	var roman := crowd.profile()
	var layout := ArenaSection.load_layout()
	var camera := Camera3D.new()
	camera.fov = RiposteKits.camera_profile().fov_degrees
	world.add_child(camera)
	camera.current = true
	var bays: Array[int] = [layout.bay_near(PI * 0.5), layout.bay_near(-PI * 0.5)]
	var labels: PackedStringArray = ["south", "north"]
	var pitch := deg_to_rad(RiposteKits.camera_profile().pitch_degrees)
	for cheer: bool in [false, true]:
		var packed := roman.pose_scene(cheer)
		if packed == null:
			continue
		for tier: int in layout.tier_count():
			for side: int in 2:
				var pose := layout.pose_for(tier, bays[side], 0)
				var holder := Node3D.new()
				holder.transform = pose
				holder.add_child(packed.instantiate())
				var worn_face := MeshInstance3D.new()
				worn_face.mesh = roman.face()
				holder.add_child(worn_face)
				var worn_hair := MeshInstance3D.new()
				worn_hair.mesh = roman.hair_style(1 if cheer else 0)
				holder.add_child(worn_hair)
				arena.add_child(holder)
				var flat := Vector3(pose.origin.x, 0.0, pose.origin.z)
				var inward := (-flat).normalized()
				var aim := pose.origin + Vector3(0.0, 1.05, 0.0)
				var distance := 4.5
				camera.position = aim + inward * cos(pitch) * distance + Vector3.UP * sin(pitch) * distance
				camera.look_at(aim, Vector3.UP)
				await process_frame
				await process_frame
				var kind := "cheer" if cheer else "seated"
				_save(viewport, out, "inspect_%s_t%d_%s" % [kind, tier, labels[side]])
				if tier == 0 and side == 0:
					var side_dir := inward.cross(Vector3.UP).normalized()
					camera.position = aim + side_dir * 2.4 + Vector3.UP * 0.15
					camera.look_at(aim, Vector3.UP)
					await process_frame
					await process_frame
					_save(viewport, out, "inspect_%s_side" % kind)
				holder.free()
	camera.free()


## Front, side, and rear of the head, then the gameplay distance.
## The close shots check the construction. The far shot is the acceptance camera.
func _hair_views(viewport: SubViewport, world: Node3D, out: String) -> void:
	var rules := StandardDuelRules.create()
	var catalog := RiposteKits.build_catalog()
	var camera := Camera3D.new()
	camera.fov = RiposteKits.camera_profile().fov_degrees
	world.add_child(camera)
	camera.current = true
	for child: Node in world.get_children():
		if child is FighterPresentation3D:
			(child as Node3D).visible = false
	var names: PackedStringArray = ["ranger", "training"]
	var skins: Array[StringName] = [&"", RiposteKits.SKIN_DUELIST_TRAINING]
	var head := Vector3(0.0, 1.6, 0.0)
	for index: int in 2:
		var chosen: Array[StringName] = [skins[index], &""]
		var kits := DuelKits.resolve(catalog, rules, chosen)
		var spec := rules.combatant(0)
		var proxy := FighterPresentation3D.create(0, DuelSide.Id.LIGHT_SOUTH, kits.combatant(0), spec.fighter.push_radius, spec)
		world.add_child(proxy)
		var state := DuelSetup.new_state(rules, 1)
		var row := SnapshotProjector.project(state, rules).fighter(0)
		proxy.apply_pose(Vector3.ZERO, 0.0, row.weapon_angle, row, 1.0 / 60.0)
		var shots: Array[Dictionary] = [
			{"name": "front", "at": Vector3(0.0, 1.55, 2.4)},
			{"name": "side", "at": Vector3(2.4, 1.55, 0.15)},
			{"name": "rear", "at": Vector3(0.0, 1.55, -2.4)},
			{"name": "gameplay", "at": Vector3(0.0, 10.4, 12.6)},
		]
		for shot: Dictionary in shots:
			camera.position = shot["at"]
			camera.look_at(head if String(shot["name"]) != "gameplay" else Vector3(0.0, 0.8, 0.0), Vector3.UP)
			await process_frame
			await process_frame
			_save(viewport, out, "hair_%s_%s" % [names[index], String(shot["name"])])
		proxy.queue_free()
	camera.free()


func _frame_sample() -> void:
	var samples: Array[float] = []
	for _i in 60:
		await process_frame
		samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	samples.sort()
	var median: float = samples[int(float(samples.size()) * 0.5)]
	var high: float = samples[mini(samples.size() - 1, int(float(samples.size()) * 0.95))]
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("RIPOSTE_FRAME ms median", median, "p95", high, "draws", draws, "prims", prims)

func _fighters(world: Node3D, rules: DuelRules, kits: DuelKits) -> void:
	var state := DuelSetup.new_state(rules, 1)
	var snap := SnapshotProjector.project(state, rules)
	for slot in 2:
		var row := snap.fighter(slot)
		var spec := rules.combatant(slot)
		var proxy := FighterPresentation3D.create(slot, row.side, kits.combatant(slot), spec.fighter.push_radius, spec)
		world.add_child(proxy)
		proxy.apply_pose(ArenaTransform.to_world(row.x, row.y), row.facing, row.weapon_angle, row, 1.0 / 60.0)


func _grayscale(arena: Node, on: bool) -> void:
	var env := arena.get_node("Environment") as WorldEnvironment
	env.environment.adjustment_enabled = on
	env.environment.adjustment_saturation = 0.0 if on else 1.0


func _figure(arena: Node3D, mesh: Mesh, pose: Transform3D) -> void:
	var figure := MeshInstance3D.new()
	figure.mesh = mesh
	figure.transform = pose
	figure.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	arena.add_child(figure)


func _save(viewport: SubViewport, out: String, shot_name: String) -> void:
	var image := viewport.get_texture().get_image()
	image.save_png(out.path_join("%s.png" % shot_name))
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("RIPOSTE_LOOK", shot_name, "draws", draw_calls, "prims", primitives)


func _door_shots(viewport: SubViewport, world: Node3D, arena: Node3D, out: String) -> void:
	_grayscale(arena, false)
	if arena.crowd() != null:
		arena.crowd().visible = false
	var bowl := arena.get_node_or_null("Bowl")
	if bowl is Node3D:
		(bowl as Node3D).visible = true
	var camera := Camera3D.new()
	camera.fov = RiposteKits.camera_profile().fov_degrees
	world.add_child(camera)
	camera.current = true
	var views: Array[Dictionary] = [
		{"name": "door_south_front", "at": Vector3(0.0, 1.5, 5.6), "look": Vector3(0.0, 1.05, 8.5)},
		{"name": "door_south_oblique", "at": Vector3(2.6, 1.7, 6.0), "look": Vector3(0.2, 1.0, 8.4)},
		{"name": "door_south_jamb_pos", "at": Vector3(1.55, 1.05, 7.15), "look": Vector3(1.12, 0.85, 8.38)},
		{"name": "door_south_jamb_neg", "at": Vector3(-1.55, 1.05, 7.15), "look": Vector3(-1.12, 0.85, 8.38)},
		{"name": "door_north_front", "at": Vector3(0.0, 1.5, -5.6), "look": Vector3(0.0, 1.05, -8.5)},
		{"name": "door_north_oblique", "at": Vector3(-2.6, 1.7, -6.0), "look": Vector3(-0.2, 1.0, -8.4)},
		{"name": "door_north_jamb_pos", "at": Vector3(1.55, 1.05, -7.15), "look": Vector3(1.12, 0.85, -8.38)},
		{"name": "door_north_jamb_neg", "at": Vector3(-1.55, 1.05, -7.15), "look": Vector3(-1.12, 0.85, -8.38)},
	]
	for view: Dictionary in views:
		camera.position = view["at"]
		camera.look_at(view["look"], Vector3.UP)
		await process_frame
		await process_frame
		_save(viewport, out, String(view["name"]))
	camera.free()


func _step_shots(viewport: SubViewport, world: Node3D, arena: Node3D, out: String) -> void:
	arena.visible = false
	_show_fighters(world, false)
	var rules := StandardDuelRules.pit()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var camera := DuelCameraRig.new()
	world.add_child(camera)
	camera.configure(RiposteKits.camera_profile())
	var state := DuelSetup.new_state(rules, 1)
	var opening := SnapshotProjector.project(state, rules)
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), camera, rules.platform_radius, rules.edge_warning_inset, opening)
	world.add_child(presenter)
	presenter.push(opening, [])
	presenter.render(1.0, 0.05)
	camera.camera().current = true
	await process_frame
	await process_frame
	_save(viewport, out, "sand_clean")
	state.fighter(0).x += 0.45
	presenter.push(SnapshotProjector.project(state, rules), [])
	presenter.render(1.0, 0.05)
	await process_frame
	await process_frame
	_save(viewport, out, "sand_step")
	for _step in 4:
		state.fighter(0).x += 0.4
		presenter.push(SnapshotProjector.project(state, rules), [])
		presenter.render(1.0, 0.05)
	await process_frame
	await process_frame
	_save(viewport, out, "sand_walk")
	presenter.render(1.0, 0.05)
	await process_frame
	await process_frame
	_save(viewport, out, "sand_stop")
	state.fighter(0).facing += 0.8
	presenter.push(SnapshotProjector.project(state, rules), [])
	presenter.render(1.0, 0.05)
	await process_frame
	await process_frame
	_save(viewport, out, "sand_pivot")
	state.fighter(0).x += 0.25
	presenter.push(SnapshotProjector.project(state, rules), [])
	presenter.render(1.0, 0.05)
	await process_frame
	await process_frame
	_save(viewport, out, "sand_shove")


func _bench(viewport: SubViewport, world: Node3D, arena: Node3D) -> void:
	_grayscale(arena, false)
	var crowd: CrowdStage = arena.crowd()
	_show_fighters(world, false)
	if crowd != null:
		crowd.visible = false
	await _bench_sample(viewport, "bowl")
	if crowd != null:
		crowd.visible = true
		await _bench_sample(viewport, "seated")
		crowd.react(CrowdDirector.CUE_VICTORY, 1.0)
		crowd.advance(1.0, null, false)
		await _bench_sample(viewport, "cheer")
	_show_fighters(world, true)
	await _bench_sample(viewport, "fighters")


func _show_fighters(world: Node3D, shown: bool) -> void:
	for child: Node in world.get_children():
		if child is FighterPresentation3D:
			(child as Node3D).visible = shown


func _bench_sample(viewport: SubViewport, label: String) -> void:
	for _warm in 20:
		await process_frame
	var process_ms: Array[float] = []
	for _frame in 60:
		await process_frame
		process_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	process_ms.sort()
	var count := process_ms.size()
	var mid := int(float(count) * 0.5)
	var high := mini(count - 1, int(float(count) * 0.95))
	var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	print("RIPOSTE_BENCH", label, "process_median", process_ms[mid], "p95", process_ms[high], "max", process_ms[count - 1], "draws", draws, "prims", prims, "size", viewport.size)
