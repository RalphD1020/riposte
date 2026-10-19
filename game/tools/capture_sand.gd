extends SceneTree

## Compatibility look at the sand disc: clean, one step, a trail, a burst, a kill.
##
##   godot --path game --rendering-method gl_compatibility -s res://tools/capture_sand.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://../.reports/arena_look")
	DirAccess.make_dir_recursive_absolute(out)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var arena := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, rules.spawn_offset, 4)
	world.add_child(arena)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	rig.look_from(DuelSide.Id.LIGHT_SOUTH)
	var options := PresentationOptions.new()
	rig.frame(Vector3(0.0, 0.0, -0.4), Vector3(0.0, 0.0, 0.4), 0.0, options, true)
	rig.camera().current = true
	var surface := arena.surface()
	await _shot(viewport, out, "sand_clean")
	surface.stamp_circle(Vector2(0.2, -1.2), ArenaSurfaceState.WALK_RADIUS, ArenaSurfaceState.WALK_STRENGTH)
	surface.flush()
	await _shot(viewport, out, "sand_step")
	for step: int in 6:
		var along := -1.2 - float(step) * 0.75
		surface.stamp_circle(Vector2(0.15 if step % 2 == 0 else -0.15, along), ArenaSurfaceState.WALK_RADIUS, ArenaSurfaceState.WALK_STRENGTH)
	surface.stamp_circle(Vector2(1.4, 0.2), ArenaSurfaceState.KILL_RADIUS, ArenaSurfaceState.KILL_STRENGTH)
	surface.stamp_ellipse(Vector2(-0.4, 0.6), Vector2(1.0, 0.2), ArenaSurfaceState.BURST_LONG, ArenaSurfaceState.BURST_LAT, ArenaSurfaceState.BURST_STRENGTH)
	surface.flush()
	await _shot(viewport, out, "sand_marked")
	print("RIPOSTE_SAND", surface.resolution(), surface.update_count())
	quit()


func _shot(viewport: SubViewport, out: String, shot_name: String) -> void:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(out.path_join("%s.png" % shot_name))
