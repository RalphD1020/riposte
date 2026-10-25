extends SceneTree

## Dev capture for the fighter shadow look. The shipping arena and two fighter
## proxies at the match camera: one standing with the sword out, one fallen.
## Writes the full frame, a nearest-scaled crop of the shadows so the texels
## can be counted, and a short walk-and-turn sequence to show crawl. Prints the
## effective runtime shadow settings, an estimate of the shadow texel size, and
## measured render time. Not a test.
##
##   godot --path game --rendering-method gl_compatibility -s res://tools/capture_shadows.gd -- --label=base
##
## One override per run: `--size=512` (directional shadow map), `--blur=1.5` (key
## `shadow_blur`), `--filter=0` (directional soft-shadow filter quality, 0 is
## hard), `--distance=20` (key `directional_shadow_max_distance`),
## `--normal-bias=0.2` (key `shadow_normal_bias`), `--pitch=-40` and `--yaw=180`
## (key rotation, degrees), `--sword-casts=false` (the authored sword leaves
## the shadow pass).

const SIZE := Vector2i(1280, 720)
const CROP := Rect2i(448, 200, 384, 260)
const CROP_SCALE := 3
const WARM_FRAMES := 30
const BENCH_FRAMES := 120
const WALK_FRAMES := 6

var _viewport: SubViewport
var _out: String = ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var label := "base"
	var atlas := -1
	var blur := -1.0
	var distance := -1.0
	var normal_bias := -1.0
	var pitch := -1000.0
	var yaw := -1000.0
	var filter := -1
	var sword_casts := true
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--sword-casts=false":
			sword_casts = false
		elif argument.begins_with("--filter="):
			filter = int(argument.trim_prefix("--filter="))
		elif argument.begins_with("--label="):
			label = argument.trim_prefix("--label=")
		elif argument.begins_with("--size="):
			atlas = int(argument.trim_prefix("--size="))
		elif argument.begins_with("--blur="):
			blur = float(argument.trim_prefix("--blur="))
		elif argument.begins_with("--distance="):
			distance = float(argument.trim_prefix("--distance="))
		elif argument.begins_with("--normal-bias="):
			normal_bias = float(argument.trim_prefix("--normal-bias="))
		elif argument.begins_with("--pitch="):
			pitch = float(argument.trim_prefix("--pitch="))
		elif argument.begins_with("--yaw="):
			yaw = float(argument.trim_prefix("--yaw="))
	_out = ProjectSettings.globalize_path("res://../.reports/shadows/%s" % label)
	DirAccess.make_dir_recursive_absolute(_out)
	if atlas > 0:
		RenderingServer.directional_shadow_atlas_set_size(atlas, true)
	if filter >= 0:
		RenderingServer.directional_soft_shadow_filter_set_quality(filter as RenderingServer.ShadowQuality)
	_viewport = SubViewport.new()
	_viewport.size = SIZE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	var world := Node3D.new()
	_viewport.add_child(world)
	var rules := StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	var arena := ArenaScaffold.create(kits.arena, rules.platform_radius, rules.edge_warning_inset, rules.spawn_offset, 4)
	world.add_child(arena)
	var key := arena.find_child("KeyLight", true, false) as DirectionalLight3D
	if blur >= 0.0:
		key.shadow_blur = blur
	if distance > 0.0:
		key.directional_shadow_max_distance = distance
	if normal_bias >= 0.0:
		key.shadow_normal_bias = normal_bias
	if pitch > -900.0 or yaw > -900.0:
		var rotation := key.rotation_degrees
		if pitch > -900.0:
			rotation.x = pitch
		if yaw > -900.0:
			rotation.y = yaw
		key.rotation_degrees = rotation
	var state := DuelSetup.new_state(rules, 1)
	var snap := SnapshotProjector.project(state, rules)
	var standing := _proxy(world, rules, kits, snap, 0)
	var fallen := _proxy(world, rules, kits, snap, 1)
	if not sword_casts:
		for proxy: FighterPresentation3D in [standing, fallen]:
			if proxy.weapon_model() != null:
				_cast_off(proxy.weapon_model())
	var stand_row := snap.fighter(0)
	var fall_row := snap.fighter(1)
	var stand_at := Vector3(-0.9, 0.0, 0.0)
	var fall_at := Vector3(0.9, 0.0, 0.4)
	fall_row.health = 0.0
	for _i in 150:
		fallen.apply_pose(fall_at, PI * 0.5, 0.0, fall_row, 1.0 / 60.0)
	standing.apply_pose(stand_at, 0.0, 1.3, stand_row, 1.0 / 60.0)
	var options := PresentationOptions.new()
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	rig.look_from(DuelSide.Id.LIGHT_SOUTH)
	rig.frame(stand_at, fall_at, 0.0, options, true)
	rig.camera().current = true
	for _i in WARM_FRAMES:
		await process_frame
	_save("frame")
	_save_crop("crop")
	for step: int in WALK_FRAMES:
		standing.apply_pose(stand_at + Vector3(0.05 * float(step), 0.0, 0.03 * float(step)), 0.12 * float(step), 1.3, stand_row, 1.0 / 60.0)
		await process_frame
		await process_frame
		_save_crop("walk_%d" % step)
	_report(label, key, rig.camera())
	await _bench(label)
	print("RIPOSTE_SHADOW_DIR ", _out)
	quit()


func _cast_off(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child: Node in node.get_children():
		_cast_off(child)


func _proxy(world: Node3D, rules: DuelRules, kits: DuelKits, snap: PresentationSnapshot, slot: int) -> FighterPresentation3D:
	var row := snap.fighter(slot)
	var spec := rules.combatant(slot)
	var proxy := FighterPresentation3D.create(slot, row.side, kits.combatant(slot), spec.fighter.push_radius, spec)
	world.add_child(proxy)
	return proxy


## The ortho fit is the camera frustum cut at the shadow distance, seen from
## the light. Its wider side over the atlas edge is an estimate of one texel,
## not a measurement of Godot's own fit.
func _report(label: String, key: DirectionalLight3D, camera: Camera3D) -> void:
	var atlas := int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size"))
	var light_basis := key.global_transform.basis
	var far := minf(key.directional_shadow_max_distance, camera.far)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for depth: float in [camera.near, far]:
		for corner: Vector2 in [Vector2(0, 0), Vector2(SIZE.x, 0), Vector2(0, SIZE.y), Vector2(SIZE.x, SIZE.y)]:
			var point := camera.project_position(corner, depth)
			var local := light_basis.inverse() * point
			lo = Vector2(minf(lo.x, local.x), minf(lo.y, local.y))
			hi = Vector2(maxf(hi.x, local.x), maxf(hi.y, local.y))
	var span := maxf(hi.x - lo.x, hi.y - lo.y)
	var used := _atlas_override()
	var size := used if used > 0 else atlas
	print("RIPOSTE_SHADOW_SETTINGS label %s method %s directional_map %d used_directional_map %d project_filter %d mode %d max_distance %.1f blur %.2f bias %.3f normal_bias %.3f pancake %.1f msaa %d" % [
		label, RenderingServer.get_current_rendering_method(), atlas, size,
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")), key.directional_shadow_mode,
		key.directional_shadow_max_distance, key.shadow_blur, key.shadow_bias, key.shadow_normal_bias, key.directional_shadow_pancake_size,
		int(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d")),
	])
	print("RIPOSTE_SHADOW_TEXEL label %s fit_span_m %.2f texel_estimate_cm %.2f (estimate)" % [label, span, span / float(size) * 100.0])


func _atlas_override() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--size="):
			return int(argument.trim_prefix("--size="))
	return -1


func _bench(label: String) -> void:
	var rid := _viewport.get_viewport_rid()
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	for _i in BENCH_FRAMES:
		await process_frame
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
	gpu.sort()
	cpu.sort()
	var count := gpu.size()
	var mid := int(float(count) * 0.5)
	var high := mini(count - 1, int(float(count) * 0.95))
	print("RIPOSTE_SHADOW_BENCH label %s gpu_ms median %.3f p95 %.3f max %.3f cpu_ms median %.3f p95 %.3f max %.3f draws %d prims %d" % [
		label, gpu[mid], gpu[high], gpu[count - 1], cpu[mid], cpu[high], cpu[count - 1],
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
	])


func _save(shot_name: String) -> void:
	_viewport.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))


func _save_crop(shot_name: String) -> void:
	var image := _viewport.get_texture().get_image().get_region(CROP)
	image.resize(CROP.size.x * CROP_SCALE, CROP.size.y * CROP_SCALE, Image.INTERPOLATE_NEAREST)
	image.save_png(_out.path_join(shot_name + ".png"))
