extends SceneTree

## Rendering cost of the shipping match, scenario by scenario: the product
## `MatchPresenter` on a real `DuelSimulation` at the match camera, drawn by the
## Compatibility renderer into a fixed-size viewport. Each scenario warms up,
## then records every frame's wall time, the viewport's measured CPU and GPU
## render time, draw calls and primitives, and repeats. Read-only; never a gate,
## never a unit-test assertion. Script cost on its own is `perf_report.gd`.
##
##   godot --path game --rendering-method gl_compatibility -s res://tools/perf_scenes.gd [-- --res=960x540 --repeats=3]
##
## Windowed, not `--headless`: the dummy renderer has no GPU time. The editor
## binary is a debug build, so these are desktop upper bounds, not device
## numbers.
##
## See also: /docs/architecture/PERFORMANCE.md

const FRAME := 1.0 / 60.0
const WARM_FRAMES := 60
const FRAMES := 240
const SCENARIOS: PackedStringArray = ["arena_idle_no_crowd", "arena_idle_crowd", "shadow_off", "movement", "combat_stress", "full_match"]

var _viewport: SubViewport
var _rules: DuelRules
var _kits: DuelKits


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var size := Vector2i(1280, 720)
	var repeats := 3
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--res="):
			var parts := argument.trim_prefix("--res=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif argument.begins_with("--repeats="):
			repeats = maxi(1, int(argument.trim_prefix("--repeats=")))
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	RenderingServer.viewport_set_measure_render_time(_viewport.get_viewport_rid(), true)
	_rules = StandardDuelRules.create()
	_kits = DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	_kits.match_loadout = RiposteKits.match_loadout(_kits.arena)
	print("RIPOSTE_PERF_SETUP method %s size %s atlas %d filter %d repeats %d frames %d warm %d" % [
		RenderingServer.get_current_rendering_method(), size,
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/size")),
		int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")),
		repeats, FRAMES, WARM_FRAMES,
	])
	for scenario: String in SCENARIOS:
		var runs: Array[Dictionary] = []
		for repeat: int in repeats:
			runs.append(await _measure(scenario, 11 + repeat))
		_report(scenario, runs)
	quit()


func _measure(scenario: String, seed_value: int) -> Dictionary:
	var world := Node3D.new()
	_viewport.add_child(world)
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	var simulation := DuelSimulation.create(_rules)
	var state := simulation.new_match(seed_value)
	var presenter := MatchPresenter.create(_kits, PresentationOptions.new(), rig, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(state, _rules))
	world.add_child(presenter)
	rig.camera().current = true
	if scenario == "arena_idle_no_crowd" and presenter.crowd() != null:
		presenter.crowd().visible = false
	if scenario == "shadow_off":
		var key := presenter.find_child("KeyLight", true, false) as DirectionalLight3D
		key.shadow_enabled = false
	var first := Pilot.idle()
	var second := Pilot.idle()
	if scenario == "movement":
		first = Pilot.wander(seed_value, 3)
		second = Pilot.wander(seed_value, 5)
	elif scenario == "combat_stress" or scenario == "full_match":
		first = Pilot.approach_and_tap()
		second = Pilot.approach_and_tap(1.5)
	var rid := _viewport.get_viewport_rid()
	var wall: Array[float] = []
	var gpu: Array[float] = []
	var cpu: Array[float] = []
	var draws := 0
	var prims := 0
	var last := Time.get_ticks_usec()
	var total := WARM_FRAMES + FRAMES
	if scenario == "full_match":
		total = WARM_FRAMES + FRAMES * 4
	for frame: int in total:
		var events := simulation.step(state, first.command(state, 0), second.command(state, 1))
		presenter.push(SnapshotProjector.project(state, _rules), events)
		presenter.render(1.0, FRAME)
		await process_frame
		var now := Time.get_ticks_usec()
		if frame >= WARM_FRAMES:
			wall.append(float(now - last) / 1000.0)
			gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
			cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(rid))
			draws = maxi(draws, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
			prims = maxi(prims, RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
		last = now
	presenter.detach_and_dispose()
	world.queue_free()
	await process_frame
	return {"wall": _stats(wall), "gpu": _stats(gpu), "cpu": _stats(cpu), "draws": draws, "prims": prims}


static func _stats(samples: Array[float]) -> Vector3:
	samples.sort()
	var count := samples.size()
	return Vector3(samples[int(float(count) * 0.5)], samples[mini(count - 1, int(float(count) * 0.95))], samples[count - 1])


## The median of each statistic across repeats, so one noisy run does not
## decide the number.
func _report(scenario: String, runs: Array[Dictionary]) -> void:
	var line := "RIPOSTE_PERF %s" % scenario
	for key: String in ["wall", "cpu", "gpu"]:
		var medians: Array[float] = []
		var highs: Array[float] = []
		var maxes: Array[float] = []
		for run: Dictionary in runs:
			var stats: Vector3 = run[key]
			medians.append(stats.x)
			highs.append(stats.y)
			maxes.append(stats.z)
		line += " %s_ms median %.2f p95 %.2f max %.2f" % [key, _middle(medians), _middle(highs), _middle(maxes)]
	line += " draws %d prims %d" % [int(runs[0]["draws"]), int(runs[0]["prims"])]
	print(line)


static func _middle(values: Array[float]) -> float:
	values.sort()
	return values[int(float(values.size()) * 0.5)]
