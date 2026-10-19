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
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--full":
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
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var arena := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, rules.spawn_offset, 4)
	world.add_child(arena)
	if not full:
		var layout := ArenaSection.load_layout()
		var bowl := arena.get_node_or_null("Bowl")
		if bowl is Node3D:
			(bowl as Node3D).visible = false
		if arena.crowd() != null:
			arena.crowd().visible = false
		if layout.issues().is_empty():
			var watched := PackedInt32Array([layout.bay_near(PI * 0.5), layout.bay_near(-PI * 0.5)])
			var skin := CrowdMeshes.part(false, "skin")
			var cloth := CrowdMeshes.part(false, "fabric")
			for bay_index: int in watched:
				for tier: int in layout.tier_count():
					for slot: int in layout.slots_in_bay(tier):
						var pose := layout.pose_for(tier, bay_index, slot)
						_figure(arena, skin, pose)
						_figure(arena, cloth, pose)
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
	for shot: Dictionary in shots:
		var gap := float(shot["gap"])
		rig.look_from(shot["side"] as DuelSide.Id)
		rig.frame(Vector3(0.0, 0.0, -gap * 0.5), Vector3(0.0, 0.0, gap * 0.5), 0.0, options, true)
		rig.camera().current = true
		await process_frame
		await process_frame
		_save(viewport, out, "%s%s" % ["full_" if full else "", String(shot["name"])])
	print("RIPOSTE_LOOK_DIR", out)
	quit()


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
