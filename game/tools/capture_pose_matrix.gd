extends SceneTree

## Dev capture for the visual gate: drives a real `DuelSimulation` with scripted
## commands through the real `MatchPresenter`, one rendered frame per tick, and
## saves named frames of Wolf from a close three-quarter view — resting guard,
## 0/50/100% charge, both slash directions, the centre crossing, and a thrust.
## Behavioural suites prove state; this is what a human signs the silhouette
## off against (docs/reference/testing.md, visual gate).
##
##   godot --path game --rendering-method gl_compatibility --resolution 900x900 -s res://tools/capture_pose_matrix.gd [-- --out=<dir>]

const FRAME := 1.0 / 60.0

var _simulation: DuelSimulation
var _rules: DuelRules
var _state: MatchState
var _presenter: MatchPresenter
var _camera: Camera3D
var _out: String = ""


func _init() -> void:
	_rules = StandardDuelRules.create()
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	_out = ProjectSettings.globalize_path("res://../.reports/matrix")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	var world := Node3D.new()
	root.add_child(world)
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
	await _shot("default_midguard")
	await _charge("right")
	await _tick(_command(false, true))
	await _release("right")
	await _ticks(PlayerCommand.idle(0), 60)
	## The blade rests where the cut left it, near the left guard limit, where a
	## hold can earn little; a tap brings it back so the left charge is full.
	await _tick(_command(true, false))
	await _tick(_command(false, true))
	await _ticks(PlayerCommand.idle(0), 60)
	await _shot("left_ready")
	await _charge("left")
	await _tick(_command(false, true))
	await _release("left")
	await _ticks(PlayerCommand.idle(0), 60)
	await _thrust()
	quit()


## Hold to a full charge from wherever the blade rests, capturing the gather.
func _charge(side: String) -> void:
	await _tick(_command(true, false))
	for amount: float in [0.25, 0.5, 0.75, 0.99]:
		await _hold_until_charge(amount)
		await _shot("%s_charge_%d" % [side, mini(roundi(amount * 100.0), 100)])


## Capture the release at the landmarks of the cut: 10% and 25% of its travel,
## the centre crossing, 65%, the pitch inflection, and the first recovery tick.
func _release(side: String) -> void:
	var marks := {0.10: "10", 0.25: "25", 0.65: "65"}
	var taken := {}
	var crossed := false
	var inflected := false
	for _i in 120:
		var before := _row().weapon_angle
		await _tick(PlayerCommand.idle(_state.tick))
		var row := _row()
		for mark: float in marks:
			if not taken.has(mark) and row.swing_progress >= mark and CombatPresentationField.is_swing(row.phase):
				taken[mark] = true
				await _shot("%s_release_%s" % [side, marks[mark]])
		if not crossed and signf(before) != signf(row.weapon_angle):
			crossed = true
			await _shot("%s_release_center" % side)
		if not inflected and _presenter.fighter_proxy(0).is_cut_committed():
			inflected = true
			await _shot("%s_release_pitch_inflection" % side)
		if row.phase == CombatPhase.Id.RECOVERY or (row.phase == CombatPhase.Id.NEUTRAL and crossed):
			await _shot("%s_recovery" % side)
			return


func _thrust() -> void:
	for _i in 30:
		await _tick(PlayerCommand.create(_state.tick, 0.0, 1.0, false, false, false, _i == 0))
		if _row().burst != MovementGestureState.BurstKind.NONE:
			await _shot("thrust")
			return
	await _shot("thrust")


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


func _shot(shot_name: String) -> void:
	var row := _row()
	print("%-16s angle %6.1f° phase %-14s charge %.2f launched %.2f progress %.2f" % [shot_name, rad_to_deg(row.weapon_angle), CombatPhase.Id.keys()[row.phase], row.charge, row.swing_charge, row.swing_progress])
	var feet := ArenaTransform.to_world(_state.fighter(0).x, _state.fighter(0).y)
	var facing := ArenaTransform.yaw(_state.fighter(0).facing)
	var forward := Vector3(sin(facing), 0.0, cos(facing))
	var right := forward.cross(Vector3.UP)
	_camera.look_at_from_position(feet + forward * 1.9 - right * 1.3 + Vector3(0.0, 1.35, 0.0), feet + Vector3(0.0, 1.0, 0.0), Vector3.UP)
	for _i in 2:
		_presenter.render(1.0, 0.0)
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
