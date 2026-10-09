extends SceneTree

## Dev capture for the death acceptance pass: the Wolf killed by a cut and by a
## thrust, each let play to the end with the sword dropped and the grip eased
## off, saved to .reports/death_<family>_<view>.png. In the side view the
## fighter faces image-right, so a run-through falls right and a cut-down left.
##
##   godot --path game --rendering-method gl_compatibility --resolution 900x900 -s res://tools/capture_deaths.gd

## Wall-clock seconds to let each death play out (clips and grip fade run on
## engine time; a windowed run is uncapped, so frames are not a clock).
const SETTLE_MSEC := 1500


func _init() -> void:
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	for family: DeathPresentationProfile.Family in [DeathPresentationProfile.Family.SLASH, DeathPresentationProfile.Family.STAB]:
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
		var row := first.fighter(0)
		var feet := ArenaTransform.to_world(row.x, row.y)
		var forward := Vector3(cos(row.facing), 0.0, -sin(row.facing))
		var right := Vector3(sin(row.facing), 0.0, cos(row.facing))
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.make_current()
		proxy.begin_death(family, 3)
		proxy.detach_weapon().free()
		row.health = 0.0
		var start := Time.get_ticks_msec()
		var last := start
		while Time.get_ticks_msec() - start < SETTLE_MSEC:
			var now := Time.get_ticks_msec()
			proxy.apply_pose(feet, row.facing, row.weapon_angle, row, float(now - last) / 1000.0)
			last = now
			await process_frame
		var label := "slash" if family == DeathPresentationProfile.Family.SLASH else "stab"
		for view: Array in [["side", feet + right * 3.2 + Vector3(0.0, 0.9, 0.0)], ["three_quarter", feet + right * 2.2 - forward * 1.6 + Vector3(0.0, 1.8, 0.0)]]:
			camera.look_at_from_position(view[1], feet + Vector3(0.0, 0.45, 0.0), Vector3.UP)
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png("res://../.reports/death_%s_%s.png" % [label, view[0]])
		print("RIPOSTE_CAPTURE %s clip=%s" % [label, proxy.animation_clip(PresentationKit.ANIM_DEATH)])
		world.queue_free()
		await process_frame
	await _capture_pair(rules, kits)
	quit()


## The paired read mid-beat: the victim run through and the striker holding the
## lunge a thrust's reach away, side on, 0.6 s after the kill.
func _capture_pair(rules: DuelRules, kits: DuelKits) -> void:
	var world := Node3D.new()
	root.add_child(world)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var state := DuelSetup.new_state(rules, 3)
	var first := SnapshotProjector.project(state, rules)
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), rig, rules.platform_radius, rules.edge_warning_inset, first)
	world.add_child(presenter)
	var victim := presenter.fighter_proxy(0)
	var striker := presenter.fighter_proxy(1)
	var dead := first.fighter(0)
	var alive := first.fighter(1)
	var feet := ArenaTransform.to_world(dead.x, dead.y)
	var forward := Vector3(cos(dead.facing), 0.0, -sin(dead.facing))
	var right := Vector3(sin(dead.facing), 0.0, cos(dead.facing))
	var striker_feet := feet + forward * 1.3
	victim.begin_death(DeathPresentationProfile.Family.STAB, 3)
	victim.detach_weapon().free()
	striker.begin_finisher()
	dead.health = 0.0
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.make_current()
	var start := Time.get_ticks_msec()
	var last := start
	while Time.get_ticks_msec() - start < 600:
		var now := Time.get_ticks_msec()
		var delta := float(now - last) / 1000.0
		last = now
		victim.apply_pose(feet, dead.facing, dead.weapon_angle, dead, delta)
		striker.apply_pose(striker_feet, dead.facing + PI, 0.0, alive, delta)
		await process_frame
	var middle := feet + forward * 0.65
	camera.look_at_from_position(middle + right * 4.0 + Vector3(0.0, 1.0, 0.0), middle + Vector3(0.0, 0.6, 0.0), Vector3.UP)
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://../.reports/death_pair_side.png")
	print("RIPOSTE_CAPTURE pair striker=%s finishing=%s" % [striker.animation_clip(striker.current_semantic()), striker.is_finishing()])
	world.queue_free()
	await process_frame
