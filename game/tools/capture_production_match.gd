extends SceneTree

## Dev capture for the production-body review through the real presentation
## pipeline: a real `DuelSimulation` drives the real `MatchPresenter`, and slot 0
## wears the production body candidate (a `FighterSkinKit` whose scene is the
## candidate wrapper), so the clips, `CombatPoseModifier3D` and `TwoBoneIK3D`
## pose it exactly as they pose the shipped Wolf on slot 1. The full load is
## also shot with the clavicle held at rest, and the set victory is played on
## the real `VictoryDirector` in the same dress. Saves
## .reports/production_match/<moment>_<view>.png.
##
##   godot --path game --rendering-method gl_compatibility --resolution 900x900 -s res://tools/capture_production_match.gd [-- --out=<dir>]

const FRAME := 1.0 / 60.0
const WRAPPER := "res://assets/presentation/fighters/duelist/wolf_production_wrapper.tscn"
const GAMEPLAY_PITCH_DEG := 48.0
const GAMEPLAY_DISTANCE := 14.0
const GAMEPLAY_FOV_DEG := 40.0
## The victory beats (FighterVictoryProfile): the held overhead load and the hero frame.
const VICTORY_BEATS := {"hold": 1.25, "hero": 2.4}

var _simulation: DuelSimulation
var _rules: DuelRules
var _kits: DuelKits
var _world: Node3D
var _state: MatchState
var _presenter: MatchPresenter
var _camera: Camera3D
var _out: String = ""


func _init() -> void:
	_rules = StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	var candidate := FighterSkinKit.new()
	candidate.skin_id = &"capture.wolf_production"
	candidate.scene = load(WRAPPER) as PackedScene
	kits.combatant(0).fighter_skin = candidate
	_kits = kits
	_out = ProjectSettings.globalize_path("res://../.reports/production_match")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
	_world = world
	var rig := DuelCameraRig.new()
	world.add_child(rig)
	rig.configure(RiposteKits.camera_profile())
	_simulation = DuelSimulation.create(_rules)
	_state = _simulation.new_match(3)
	_presenter = MatchPresenter.create(kits, PresentationOptions.new(), rig, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(_state, _rules))
	world.add_child(_presenter)
	_camera = Camera3D.new()
	world.add_child(_camera)
	_camera.make_current()
	_run.call_deferred()


func _run() -> void:
	while _state.phase == MatchPhase.Id.ROUND_INTRO:
		await _tick(PlayerCommand.idle(_state.tick))
	await _ticks(PlayerCommand.idle(0), 40)
	await _shot("guard")
	await _tick(_command(true, false))
	await _hold_until_charge(0.99)
	await _shot("charge_full")
	## The same frame with the girdle held at rest, for comparison.
	var chain := _presenter.fighter_proxy(0).rig().combat_pose()
	var clavicle := chain.clavicle
	chain.clavicle = null
	await _shot("charge_full_no_clavicle")
	chain.clavicle = clavicle
	await _tick(_command(false, true))
	var crossed := false
	for _i in 120:
		var before := _row().weapon_angle
		await _tick(PlayerCommand.idle(_state.tick))
		if not crossed and signf(before) != signf(_row().weapon_angle):
			crossed = true
			await _shot("cut_center")
		if _row().phase == CombatPhase.Id.RECOVERY:
			await _shot("cut_recovery")
			break
	await _ticks(PlayerCommand.idle(0), 60)
	for _i in 30:
		await _tick(PlayerCommand.create(_state.tick, 0.0, 1.0, false, false, false, _i == 0))
		if _row().burst != MovementGestureState.BurstKind.NONE:
			break
	await _shot("thrust")
	_world.queue_free()
	await process_frame
	await _victory()
	print("RIPOSTE_CAPTURE production_match -> %s" % _out)
	quit()


## The set victory on the real `VictoryDirector`, the candidate dressed as in
## the match: the held overhead load and the settled hero frame, from the
## director's own camera and a shoulder close-up.
func _victory() -> void:
	var director := VictoryDirector.create(_kits.combatant(0), DuelSide.Id.LIGHT_SOUTH, _rules.combatant(0).fighter.push_radius, _rules.combatant(0).weapon.blade_base_radius, _rules.combatant(0).weapon.tip_radius)
	root.add_child(director)
	await process_frame
	for beat: String in VICTORY_BEATS:
		while director.elapsed() < float(VICTORY_BEATS[beat]):
			director.advance(FRAME)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("victory_%s_director.png" % beat))
		var actor := director.actor()
		var at := actor.global_position
		var close := Camera3D.new()
		director.add_child(close)
		close.fov = 50.0
		var facing := actor.global_transform.basis.z.normalized()
		close.look_at_from_position(at + facing * 1.2 + Vector3(0.6, 1.7, 0.0), at + Vector3(0.0, 1.4, 0.0), Vector3.UP)
		close.make_current()
		for _i in 2:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("victory_%s_closeup.png" % beat))
		close.queue_free()
		await process_frame


func _hold_until_charge(target: float) -> void:
	for _i in 240:
		if _row().charge >= target:
			return
		await _tick(PlayerCommand.idle(_state.tick))


func _command(pressed: bool, released: bool) -> PlayerCommand:
	return PlayerCommand.create(_state.tick, 0.0, 0.0, pressed, released)


func _row() -> PresentationFighter:
	return _presenter.current_snapshot().fighter(0)


func _ticks(command: PlayerCommand, count: int) -> void:
	for _i in count:
		command.tick = _state.tick
		await _tick(command)


func _tick(command: PlayerCommand) -> void:
	var events := _simulation.step(_state, command, PlayerCommand.idle(_state.tick))
	_presenter.push(SnapshotProjector.project(_state, _rules), events)
	_presenter.render(1.0, FRAME)
	await process_frame


## Front, three-quarter and side close framings, a shoulder/neck/mantle
## close-up, and the shipped gameplay camera's pitch and distance.
func _shot(moment: String) -> void:
	var feet := ArenaTransform.to_world(_state.fighter(0).x, _state.fighter(0).y)
	var facing := ArenaTransform.yaw(_state.fighter(0).facing)
	var forward := Vector3(sin(facing), 0.0, cos(facing))
	var right := forward.cross(Vector3.UP)
	var pitch := deg_to_rad(GAMEPLAY_PITCH_DEG)
	var chest := feet + Vector3(0.0, 1.0, 0.0)
	var views := [
		["front", feet + forward * 2.6 + Vector3(0.0, 1.2, 0.0), chest],
		["three_quarter", feet + forward * 1.9 - right * 1.3 + Vector3(0.0, 1.35, 0.0), chest],
		["side", feet - right * 2.6 + Vector3(0.0, 1.2, 0.0), chest],
		["closeup", feet + forward * 1.0 - right * 0.55 + Vector3(0.0, 1.75, 0.0), feet + Vector3(0.0, 1.38, 0.0)],
		["gameplay", chest + (forward * 0.35 - right).normalized() * GAMEPLAY_DISTANCE * cos(pitch) + Vector3.UP * GAMEPLAY_DISTANCE * sin(pitch), chest],
	]
	for view: Array in views:
		_camera.fov = GAMEPLAY_FOV_DEG if view[0] == "gameplay" else 50.0
		_camera.look_at_from_position(view[1], view[2], Vector3.UP)
		for _i in 2:
			_presenter.render(1.0, 0.0)
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(_out.path_join("%s_%s.png" % [moment, view[0]]))
