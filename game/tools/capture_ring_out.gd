extends SceneTree

## Compatibility look at a real walk off the south edge: both fighters, the
## gameplay camera, and the dropped sword. Not a test. Writes PNGs and
## ring_out.txt under .reports/arena_look.
##
##   godot --path game --rendering-method gl_compatibility -s res://tools/capture_ring_out.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://../.reports/arena_look")
	DirAccess.make_dir_recursive_absolute(out)
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
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var sim := DuelSimulation.create(rules)
	var state := sim.new_match(3)
	var light := 0
	if state.fighter(1).side == DuelSide.Id.LIGHT_SOUTH:
		light = 1
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), rig, rules.platform_radius, rules.edge_warning_inset, SnapshotProjector.project(state, rules))
	world.add_child(presenter)
	var placed := false
	var fell: DuelEvent = null
	var ticks := 0
	while fell == null and ticks < 800:
		if state.phase == MatchPhase.Id.ROUND_ACTIVE and not placed:
			placed = true
			var walker := state.fighter(light)
			walker.x = 0.35
			walker.y = -(rules.platform_radius - 1.15)
			walker.vx = 0.0
			walker.vy = 0.0
			var other := state.fighter(1 - light)
			other.x = 0.0
			other.y = 3.0
			other.vx = 0.0
			other.vy = 0.0
			presenter.push(SnapshotProjector.project(state, rules), [])
			presenter.render(1.0, SimulationTimebase.TICK_SECONDS)
			await _save(viewport, out, "ring_before")
		var commands: Array[PlayerCommand] = [PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick)]
		if placed:
			commands[light] = PlayerCommand.create(state.tick, 0.0, -1.0)
		var events := sim.step(state, commands[0], commands[1])
		presenter.push(SnapshotProjector.project(state, rules), events)
		if placed:
			presenter.render(1.0, SimulationTimebase.TICK_SECONDS)
		for event: DuelEvent in events:
			if event.type == DuelEventTypes.RING_OUT and event.actor == light:
				fell = event
		ticks += 1
	var lines: PackedStringArray = []
	lines.append("platform_radius %.4f" % rules.platform_radius)
	lines.append("placed %s light_slot %d ticks %d" % [placed, light, ticks])
	if fell == null:
		var where := state.fighter(light)
		lines.append("NO RING_OUT sim_r %.3f phase %d" % [SimMath.length(where.x, where.y), state.phase])
	else:
		var sim_x := fell.number(DuelEventKeys.POSITION_X)
		var sim_y := fell.number(DuelEventKeys.POSITION_Y)
		var sim_r := SimMath.length(sim_x, sim_y)
		lines.append("RING_OUT sim (%.3f, %.3f) r %.4f past disc by %.4f" % [sim_x, sim_y, sim_r, sim_r - rules.platform_radius])
		await _watch(presenter, viewport, out, lines, light, rules.platform_radius)
	_report_floor(presenter, lines)
	_report_bodies(presenter, lines)
	presenter.queue_free()
	await process_frame
	await process_frame
	var again := MatchPresenter.create(kits, PresentationOptions.new(), rig, rules.platform_radius, rules.edge_warning_inset, SnapshotProjector.project(sim.new_match(3), rules))
	world.add_child(again)
	var rebuilt := _body_names(again)
	lines.append("rematch colliders %d" % rebuilt.size())
	for body_name: String in rebuilt:
		lines.append("rematch body %s" % body_name)
	var text := "\n".join(lines)
	var file := FileAccess.open(out.path_join("ring_out.txt"), FileAccess.WRITE)
	file.store_string(text + "\n")
	file.close()
	print(text)
	print("RIPOSTE_RING_DIR", out)
	quit()


func _watch(presenter: MatchPresenter, viewport: SubViewport, out: String, lines: PackedStringArray, light: int, radius: float) -> void:
	var proxy := presenter.fighter_proxy(light)
	for frame: int in 90:
		presenter.render(1.0, 1.0 / 60.0)
		await process_frame
		if frame == 2:
			await _save(viewport, out, "ring_cross")
			_pose(lines, "cross", proxy, radius)
		elif frame == 18:
			await _save(viewport, out, "ring_drop")
		elif frame == 70:
			await _save(viewport, out, "ring_fallen")
			_pose(lines, "fallen", proxy, radius)
	lines.append("fall_request %s drop_released %s corpse_falling %s" % [proxy.has_fall_request(), presenter.has_drop_released(light), proxy.is_corpse_falling()])
	var weapon := _find_weapon(presenter)
	if weapon == null:
		lines.append("dropped weapon absent")
	else:
		var weapon_r := Vector2(weapon.global_position.x, weapon.global_position.z).length()
		lines.append("dropped weapon y %.3f r %.3f" % [weapon.global_position.y, weapon_r])
	var camera := _find_camera(presenter.get_parent())
	if camera != null:
		lines.append("camera pitch_deg %.2f distance %.2f" % [-rad_to_deg(camera.rotation.x), camera.position.length()])


func _pose(lines: PackedStringArray, label: String, proxy: FighterPresentation3D, radius: float) -> void:
	var flat := Vector2(proxy.global_position.x, proxy.global_position.z).length()
	lines.append("%s proxy (%.3f, %.3f, %.3f) r %.3f past %.3f" % [label, proxy.global_position.x, proxy.global_position.y, proxy.global_position.z, flat, flat - radius])


func _report_floor(presenter: MatchPresenter, lines: PackedStringArray) -> void:
	var paving := presenter.find_child("SandSurface", true, false)
	var highest := -100.0
	if paving != null:
		for instance: MeshInstance3D in _meshes(paving):
			var mesh := instance.mesh
			if mesh == null:
				continue
			for surface: int in mesh.get_surface_count():
				var vertices: PackedVector3Array = mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
				for vertex: Vector3 in vertices:
					highest = maxf(highest, (instance.global_transform * vertex).y)
	lines.append("floor_max_y %.4f" % highest)


func _report_bodies(node: Node, lines: PackedStringArray) -> void:
	var names := _body_names(node)
	lines.append("colliders %d" % names.size())
	for body_name: String in names:
		lines.append("body %s" % body_name)


func _body_names(node: Node) -> PackedStringArray:
	var names := PackedStringArray()
	if node is CollisionObject3D:
		names.append(String(node.name))
	for child: Node in node.get_children():
		names.append_array(_body_names(child))
	return names


func _meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		found.append(node as MeshInstance3D)
	for child: Node in node.get_children():
		found.append_array(_meshes(child))
	return found


func _find_weapon(node: Node) -> DroppedWeapon3D:
	if node is DroppedWeapon3D:
		return node as DroppedWeapon3D
	for child: Node in node.get_children():
		var found := _find_weapon(child)
		if found != null:
			return found
	return null


func _find_camera(node: Node) -> Camera3D:
	if node is Camera3D:
		return node as Camera3D
	for child: Node in node.get_children():
		var found := _find_camera(child)
		if found != null:
			return found
	return null


func _save(viewport: SubViewport, out: String, shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(out.path_join("%s.png" % shot_name))
	var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
	var frame_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	print("RIPOSTE_RING", shot_name, "draws", draw_calls, "prims", primitives, "process_ms", frame_ms)
