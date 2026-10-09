extends SceneTree

## Dev capture for the Mittelhut acceptance gate: one Wolf posed at a sweep of
## weapon angles, each saved to .reports/guard_<deg>.png, so the elbow
## silhouette can be judged from a close three-quarter view.
##
##   godot --path game --rendering-method gl_compatibility --resolution 900x900 -s res://tools/capture_guard_angles.gd


func _init() -> void:
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	var world := Node3D.new()
	root.add_child(world)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var state := DuelSetup.new_state(rules, 3)
	var first := SnapshotProjector.project(state, rules)
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), rig, rules.platform_radius, rules.edge_warning_inset, first)
	world.add_child(presenter)
	var proxy := presenter.fighter_proxy(0)
	var camera := Camera3D.new()
	world.add_child(camera)
	var feet := ArenaTransform.to_world(state.fighter(0).x, state.fighter(0).y)
	camera.look_at_from_position(feet + Vector3(1.5, 1.3, 1.8), feet + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	camera.make_current()
	var row := first.fighter(0)
	for degrees: float in [-90.0, -45.0, 0.0, 45.0, 90.0]:
		row.weapon_angle = deg_to_rad(degrees)
		for _i in 4:
			proxy.apply_pose(feet, row.facing, row.weapon_angle, row, 1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		image.save_png("res://../.reports/guard_%d.png" % int(degrees))
	quit()
