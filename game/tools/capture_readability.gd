extends SceneTree

## Dev capture for combat readability. A real `DuelSimulation` and the product
## `MatchPresenter` at the match camera: both palettes, swings, contacts, hits
## and recovery as a frame sequence, plus the first frames of each contact and
## hit. Not a test. Writes PNGs, a perf line, and the floor color as drawn
## under .reports/readability/<variant>_<width>.
##
##   godot --path game --rendering-method gl_compatibility -s res://tools/capture_readability.gd -- --variant=base --res=1280x720
##
## Variants: `base`, `blade_hc` (the high-contrast weapon option),
## `key_neutral` (the key light's color set to white; same energy, same floor).

const FRAME := 1.0 / 60.0
const TICKS := 720
const EVERY := 24
const EVENT_SHOTS := 6

var _simulation: DuelSimulation
var _rules: DuelRules
var _state: MatchState
var _presenter: MatchPresenter
var _viewport: SubViewport
var _out: String = ""


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var variant := "base"
	var size := Vector2i(1280, 720)
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--variant="):
			variant = argument.trim_prefix("--variant=")
		elif argument.begins_with("--res="):
			var parts := argument.trim_prefix("--res=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
	_out = ProjectSettings.globalize_path("res://../.reports/readability/%s_%d" % [variant, size.x])
	DirAccess.make_dir_recursive_absolute(_out)
	_viewport = SubViewport.new()
	_viewport.size = size
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	_rules = StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	var options := PresentationOptions.new()
	options.high_contrast_weapons = variant == "blade_hc"
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	_simulation = DuelSimulation.create(_rules)
	_state = _simulation.new_match(11)
	_presenter = MatchPresenter.create(kits, options, rig, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(_state, _rules))
	world.add_child(_presenter)
	rig.camera().current = true
	if variant == "key_neutral":
		var key := _presenter.find_child("KeyLight", true, false) as DirectionalLight3D
		if key != null:
			key.light_color = Color.WHITE
	_report_setup()
	var first := Pilot.approach_and_tap()
	var second := Pilot.approach_and_tap(1.5)
	var samples: Array[float] = []
	var shots := {}
	for tick: int in TICKS:
		var events := _simulation.step(_state, first.command(_state, 0), second.command(_state, 1))
		_presenter.push(SnapshotProjector.project(_state, _rules), events)
		_presenter.render(1.0, FRAME)
		await process_frame
		samples.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		if tick % EVERY == 0:
			_save("seq_%04d" % tick)
		for event: DuelEvent in events:
			var kind := String(event.type)
			var taken: int = shots.get(kind, 0)
			if taken < EVENT_SHOTS and (event.type == DuelEventTypes.BLADE_CONTACT or event.type == DuelEventTypes.BODY_HIT):
				shots[kind] = taken + 1
				await process_frame
				_save("%s_%02d_t%04d" % [kind, taken, tick])
	samples.sort()
	var count := samples.size()
	print("RIPOSTE_READABILITY variant %s size %s process_median %.3f p95 %.3f max %.3f draws %d prims %d events %s" % [
		variant, size, samples[int(count * 0.5)], samples[mini(count - 1, int(float(count) * 0.95))], samples[count - 1],
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		str(shots),
	])
	_report_floor(variant)
	print("RIPOSTE_READABILITY_DIR ", _out)
	quit()


## What the floor is given and what lights it, before anything is drawn.
func _report_setup() -> void:
	var top := _presenter.find_child("SandSurface", true, false)
	if top != null:
		top = top.get_node_or_null("Top")
	if top is MeshInstance3D:
		var mesh_node := top as MeshInstance3D
		var material := mesh_node.material_override as StandardMaterial3D
		var arrays := mesh_node.mesh.surface_get_arrays(0)
		var has_colors: bool = arrays[Mesh.ARRAY_COLOR] != null
		if material != null:
			print("RIPOSTE_READABILITY_SAND albedo %s texture %s vertex_color_as_albedo %s mesh_colors %s unshaded %s roughness %.2f metallic %.2f specular %.2f surface_material %s" % [
				material.albedo_color.to_html(false), material.albedo_texture != null, material.vertex_color_use_as_albedo, has_colors,
				material.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, material.roughness, material.metallic, material.metallic_specular,
				mesh_node.mesh.surface_get_material(0) != null,
			])
	for light_name: String in ["KeyLight", "RimLight"]:
		var light := _presenter.find_child(light_name, true, false) as DirectionalLight3D
		if light != null:
			print("RIPOSTE_READABILITY_LIGHT %s color %s energy %.2f indirect %.2f pitch %.1f yaw %.1f shadow %s" % [
				light_name, light.light_color.to_html(false), light.light_energy, light.light_indirect_energy,
				light.rotation_degrees.x, light.rotation_degrees.y, light.shadow_enabled,
			])
	var world_env := _presenter.find_child("Environment", true, false) as WorldEnvironment
	if world_env != null:
		var env := world_env.environment
		print("RIPOSTE_READABILITY_ENV ambient %s energy %.2f source %d reflected %d tonemap %d exposure %.2f white %.2f adjustment %s glow %s" % [
			env.ambient_light_color.to_html(false), env.ambient_light_energy, env.ambient_light_source, env.reflected_light_source,
			env.tonemap_mode, env.tonemap_exposure, env.tonemap_white, env.adjustment_enabled, env.glow_enabled,
		])


## The lit floor as drawn, away from the fighters, beside the token it was given.
func _report_floor(variant: String) -> void:
	var image := _viewport.get_texture().get_image()
	var size := Vector2(image.get_size())
	var probes: Array[Vector2] = [Vector2(0.25, 0.667), Vector2(0.75, 0.833), Vector2(0.167, 0.333)]
	var inks := PackedStringArray()
	for at: Vector2 in probes:
		inks.append(image.get_pixelv(Vector2i(at * size)).to_html(false))
	print("RIPOSTE_READABILITY_FLOOR variant %s token %s drawn %s" % [variant, RiposteTheme.SAND.to_html(false), ", ".join(inks)])


func _save(shot_name: String) -> void:
	_viewport.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
