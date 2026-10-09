extends SceneTree

## Dev capture: two Wolves (base and Training Gear) on the authored arena,
## saved to .reports/shot_gameplay.png, or shot_close.png with `-- --close`.
## Needs a real renderer, so run it windowed, not --headless:
##
##   godot --path game --rendering-method gl_compatibility --resolution 1280x720 -s res://tools/capture_duel.gd
##
## See also: /docs/reference/assets.md


func _init() -> void:
	var rules := StandardDuelRules.create()
	var catalog := RiposteKits.build_catalog()
	var skins: Array[StringName] = [&"", RiposteKits.SKIN_DUELIST_TRAINING]
	var kits := DuelKits.resolve(catalog, rules, skins)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	var world := Node3D.new()
	root.add_child(world)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var state := DuelSetup.new_state(rules, 3)
	state.fighter(0).y = -0.9
	state.fighter(1).y = 0.9
	state.fighter(0).weapon.angle = deg_to_rad(-70.0)
	state.fighter(1).weapon.angle = deg_to_rad(40.0)
	var first := SnapshotProjector.project(state, rules)
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), rig, rules.platform_radius, rules.edge_warning_inset, first)
	world.add_child(presenter)
	for _i in 30:
		presenter.render(1.0, 1.0 / 60.0)
		await process_frame
	var close := OS.get_cmdline_user_args().has("--close")
	if close:
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(1.8, 1.7, -2.6)
		camera.look_at(Vector3(0.0, 1.0, 0.4))
		camera.make_current()
		for _i in 4:
			await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	image.save_png("res://../.reports/shot_%s.png" % ("close" if close else "gameplay"))
	quit()
