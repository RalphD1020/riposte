extends SceneTree

## Compatibility look at the seated lean, a name stand, and the match stand.
## Not a test. Writes PNGs under .reports/crowd_look.
##
##   godot --path game --rendering-method gl_compatibility -s res://tools/capture_crowd.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := ProjectSettings.globalize_path("res://../.reports/crowd_look")
	DirAccess.make_dir_recursive_absolute(out)
	var viewport := SubViewport.new()
	viewport.name = "Look"
	viewport.size = Vector2i(1280, 720)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.transparent_bg = false
	root.add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var arena := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, rules.spawn_offset, 4)
	world.add_child(arena)
	var crowd := arena.crowd()
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var options := PresentationOptions.new()
	var poses: Array[Dictionary] = [
		{"name": "seated", "cue": CrowdDirector.CUE_CHEER, "hold": false, "seconds": 1.0},
		{"name": "rising", "cue": CrowdDirector.CUE_CHEER, "hold": true, "seconds": 0.22},
		{"name": "chant", "cue": CrowdDirector.CUE_CHEER, "hold": true, "seconds": 0.7},
		{"name": "victory", "cue": CrowdDirector.CUE_VICTORY, "hold": false, "seconds": 0.7},
	]
	for side: DuelSide.Id in [DuelSide.Id.LIGHT_SOUTH, DuelSide.Id.DARK_NORTH]:
		var label := "light" if side == DuelSide.Id.LIGHT_SOUTH else "dark"
		rig.look_from(side)
		for pose: Dictionary in poses:
			crowd.reset_poses()
			crowd.react(pose["cue"], 0.8)
			if pose["hold"]:
				crowd.focus_on_side(DuelSide.Id.LIGHT_SOUTH)
				crowd.hold_chant(true)
			var left := float(pose["seconds"])
			while left > 0.0:
				var step := minf(left, 1.0 / 60.0)
				crowd.advance(step, rig.camera(), false)
				left -= step
			rig.frame(Vector3(0.0, 0.0, -4.0), Vector3(0.0, 0.0, 4.0), 0.0, options, true)
			rig.camera().current = true
			await process_frame
			await process_frame
			_save(viewport, out, "%s_%s" % [label, String(pose["name"])])
	var close := rig.camera()
	close.current = true
	for pose: Dictionary in poses:
		crowd.reset_poses()
		crowd.react(pose["cue"], 0.8)
		if pose["hold"]:
			crowd.focus_on_side(DuelSide.Id.LIGHT_SOUTH)
			crowd.hold_chant(true)
		var left := float(pose["seconds"])
		while left > 0.0:
			var step := minf(left, 1.0 / 60.0)
			crowd.advance(step, null, false)
			left -= step
		close.global_position = Vector3(0.6, 2.2, 9.2)
		close.look_at(Vector3(0.2, 1.35, 12.2), Vector3.UP)
		await process_frame
		await process_frame
		_save(viewport, out, "close_%s" % String(pose["name"]))
	print("RIPOSTE_LOOK_DIR", out)
	quit()


func _save(viewport: SubViewport, out: String, shot_name: String) -> void:
	var image := viewport.get_texture().get_image()
	image.save_png("%s/%s.png" % [out, shot_name])
