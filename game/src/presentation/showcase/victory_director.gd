class_name VictoryDirector
extends Node3D

## The set's winner, shown once when the set resolves (PRES-VICTORY-001). A
## fresh `FighterShowcaseActor` built from the winner's resolved kit performs
## the profile's authored cinematic on its own dark stage: a quick cut and the
## quick return cut — whose last stretch of streak becomes the composition's
## divider — then the gather into the duel's own high shoulder load, held
## while the stage darkens, the fanfare lands on the lock, the camera pushes
## from full body into the profile, and the announcer reads the name. No third,
## released attack. It settles into the held load's breathing idle and hands
## the screen its results (`results_ready`).
##
## Presentation-only: it never steps, reads, or writes the simulation, and it
## never touches a match proxy — the duel is already over and its presenter
## gone. It runs on real time through `advance(delta)` from the owning screen
## (PRES-TIME-001), so it is exact in headless tests and has no timer to
## outlive the screen; `finish()` skips straight to the results.
##
## Every beat fires exactly once: the beats are one time-ordered table walked
## by a monotonic cursor, so no frame, pause, skip, or long results screen can
## replay one. The charge is a held voice released on the lock — it never
## outlives the gather — and a missing take only drops its sound: the caption,
## the card, and the results still come on time.
##
## Implements: /spec/invariants.md#pres-victory-001
## See also: /docs/concepts/presentation.md

signal card_requested(display_name: String, title: String)
signal streak_requested(from: Vector2, to: Vector2)
signal results_ready

enum Stage { CINEMATIC, RESULTS }
## The cinematic's beats. Fired in time order (ties keep this order).
enum Beat { CUT_1, CUT_2, STREAK_FROM, STREAK, CHARGE, LOCK, CARD, ANNOUNCER }

const TRAIL_SAMPLES := 18
const TRAIL_MIN_SPEED := 3.0
## Trail strength while a cut is in the air; gone during the charge.
const QUICK_CUT_POTENTIAL := 0.8
## The divider is the last stretch of the return cut's streak: from this
## fraction of the cut to its end.
const STREAK_FROM := 0.8
## How far the stage darkens through the charge (ambient energy multiplier).
## It stays dark: the results composition owns the darker stage.
const CHARGE_DARKEN := 0.7
const STAGE_RADIUS := 3.0
const STAGE_COLOR := Color("2a2622")
## The held charge voice (the duel's tension slot 0; the showcase has one
## fighter).
const CHARGE_SLOT := 0

var _profile: FighterVictoryProfile
var _combatant: CombatantPresentationKit
var _side: DuelSide.Id
var _actor: FighterShowcaseActor
var _camera: Camera3D
var _environment: Environment
var _trail: SwordTrail3D
var _vfx: VfxDirector
var _audio: AudioDirector
var _time: float = 0.0
var _stage: Stage = Stage.CINEMATIC
## The beat table, sorted by time once at build, and the next beat to fire.
var _beat_ids: PackedInt32Array = PackedInt32Array()
var _beat_times: PackedFloat64Array = PackedFloat64Array()
var _next_beat: int = 0
var _charging: bool = false
var _streak_from := Vector2.ZERO
var _ambient: float = 0.0
var _previous_tip := Vector3.ZERO
var _combo_done: bool = false
var _flash_scale: float = 1.0
var _particles: float = 1.0
var _hilt: float = 0.0
var _tip: float = 0.0


static func create(combatant: CombatantPresentationKit, side: DuelSide.Id, push_radius: float, hilt: float, tip: float, flash_scale: float = 1.0, particles: float = 1.0) -> VictoryDirector:
	var director := VictoryDirector.new()
	director.name = "Victory"
	director._combatant = combatant
	director._side = side
	director._profile = combatant.victory() if combatant.victory() != null else FighterVictoryProfile.new()
	director._flash_scale = flash_scale
	director._particles = particles
	director._hilt = hilt
	director._tip = tip
	director._build(push_radius)
	return director


func _build(push_radius: float) -> void:
	_build_beats()
	_build_stage()
	_actor = FighterShowcaseActor.create(_combatant, _side, push_radius, _hilt, _tip)
	_actor.clip_finished.connect(_on_clip_finished)
	add_child(_actor)
	_trail = SwordTrail3D.create(RiposteTheme.blade_for(_side), TRAIL_SAMPLES)
	add_child(_trail)
	_vfx = VfxDirector.new()
	add_child(_vfx)
	_audio = AudioDirector.new()
	add_child(_audio)
	_camera = Camera3D.new()
	_camera.name = "VictoryCamera"
	add_child(_camera)


func _ready() -> void:
	_camera.make_current()
	if not _actor.play(_profile.combo_clip):
		_combo_done = true
	_actor.advance(0.0)
	_frame_camera(0.0)
	_previous_tip = _blade_tip()


## The profile's beats as one time-ordered table (a stable insertion sort of
## eight entries; ties keep `Beat` order).
func _build_beats() -> void:
	var times := {
		Beat.CUT_1: _profile.quick_cut_1_time,
		Beat.CUT_2: _profile.quick_cut_2_time,
		Beat.STREAK_FROM: lerpf(_profile.quick_cut_2_time, _profile.quick_cut_2_end_time, STREAK_FROM),
		Beat.STREAK: _profile.quick_cut_2_end_time,
		Beat.CHARGE: _profile.charge_start_time,
		Beat.LOCK: _profile.charge_lock_time,
		Beat.CARD: _profile.card_time,
		Beat.ANNOUNCER: _profile.announcer_time,
	}
	for beat: int in Beat.values():
		var at := float(times[beat])
		var index := _beat_times.size()
		while index > 0 and _beat_times[index - 1] > at:
			index -= 1
		_beat_ids.insert(index, beat)
		_beat_times.insert(index, at)


func _build_stage() -> void:
	var world := WorldEnvironment.new()
	world.name = "StageEnvironment"
	_environment = Environment.new()
	_environment.background_mode = Environment.BG_COLOR
	_environment.background_color = RiposteTheme.WORLD_BACKGROUND
	_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_environment.ambient_light_color = RiposteTheme.WORLD_AMBIENT
	_environment.ambient_light_energy = 0.35
	_ambient = _environment.ambient_light_energy
	world.environment = _environment
	add_child(world)
	var key := DirectionalLight3D.new()
	key.name = "Key"
	key.light_color = RiposteTheme.WORLD_KEY
	key.light_energy = 1.3
	key.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(30.0), 0.0)
	add_child(key)
	var rim := DirectionalLight3D.new()
	rim.name = "Rim"
	rim.light_color = RiposteTheme.WORLD_RIM
	rim.light_energy = 0.7
	rim.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(200.0), 0.0)
	add_child(rim)
	var floor_disc := MeshInstance3D.new()
	floor_disc.name = "Stage"
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = STAGE_RADIUS
	cylinder.bottom_radius = STAGE_RADIUS
	cylinder.height = 0.1
	floor_disc.mesh = cylinder
	floor_disc.material_override = CombatantVisuals.material(STAGE_COLOR)
	floor_disc.position.y = -0.05
	add_child(floor_disc)


## Real seconds since the showcase entered.
func advance(delta: float) -> void:
	var step := maxf(delta, 0.0)
	_time += step
	if _stage == Stage.CINEMATIC:
		_fire_beats_until(_time)
		_darken()
		_hold_charge()
	_actor.advance(step)
	_sample_trail(step)
	_trail.advance(step)
	_vfx.advance(step)
	_frame_camera(step)
	if _stage == Stage.CINEMATIC and _time >= _profile.interactive_time and _combo_done:
		_enter_results()


## Skip: jump to the settled results. Every beat that has not happened yet
## happens now — the card, the divider, the line and its caption — so a skip
## loses the motion, never the information. Idempotent.
func finish() -> void:
	if _stage == Stage.RESULTS:
		return
	_time = maxf(_time, _profile.interactive_time)
	_combo_done = true
	_darken()
	_enter_results()


func stage() -> Stage:
	return _stage


func is_cinematic() -> bool:
	return _stage == Stage.CINEMATIC


func actor() -> FighterShowcaseActor:
	return _actor


func camera() -> Camera3D:
	return _camera


func audio() -> AudioDirector:
	return _audio


func profile() -> FighterVictoryProfile:
	return _profile


func elapsed() -> float:
	return _time


## Stop every sound this showcase started. Safe during teardown.
func dispose() -> void:
	if _audio != null and is_instance_valid(_audio):
		_audio.stop_all()
	if _vfx != null and is_instance_valid(_vfx):
		_vfx.clear_all()


func _exit_tree() -> void:
	dispose()


## Fire every beat at or before `until`, each exactly once, in time order.
func _fire_beats_until(until: float) -> void:
	while _next_beat < _beat_ids.size() and until >= _beat_times[_next_beat]:
		var beat := _beat_ids[_next_beat]
		_next_beat += 1
		_fire(beat)


func _fire(beat: int) -> void:
	var weapon := _combatant.weapon
	match beat:
		Beat.CUT_1:
			_audio.play_flat(PresentationKit.CUE_SWING, weapon, 0.0, 1)
		Beat.CUT_2:
			_audio.play_flat(PresentationKit.CUE_SWING, weapon, 0.0, 2)
		Beat.STREAK_FROM:
			_streak_from = _screen(_blade_tip())
		Beat.STREAK:
			streak_requested.emit(_streak_from, _screen(_blade_tip()))
		Beat.CHARGE:
			_charging = true
		Beat.LOCK:
			_charging = false
			_audio.release_tension(CHARGE_SLOT)
			_audio.play_sting(_profile.fanfare)
		Beat.CARD:
			card_requested.emit(_profile.display_name, _profile.title)
		Beat.ANNOUNCER:
			_audio.play_voice(_profile.announcer_line, _profile.announcer_caption)


## The gather's tension, tightening toward the lock like a duel charge; held
## (never retriggered) and released by the lock beat.
func _hold_charge() -> void:
	if not _charging:
		return
	var gathered := smoothstep(_profile.charge_start_time, _profile.charge_lock_time, _time)
	_audio.hold_tension(CHARGE_SLOT, _combatant.weapon, _actor.global_position, gathered)


## How many beats have fired (tests).
func fired_beats() -> int:
	return _next_beat


## The stage darkens progressively as the load gathers and stays dark.
func _darken() -> void:
	var gathered := smoothstep(_profile.charge_start_time, _profile.charge_lock_time, _time)
	_environment.ambient_light_energy = _ambient * lerpf(1.0, CHARGE_DARKEN, gathered)


## The results never wait on a beat: any still pending fires now, once.
func _enter_results() -> void:
	_fire_beats_until(INF)
	_stage = Stage.RESULTS
	if not _actor.play(_profile.idle_clip, true):
		_actor.set_display_yaw(0.0)
	_actor.advance(0.0)
	_frame_camera(0.0)
	results_ready.emit()


func _on_clip_finished(clip: StringName) -> void:
	if clip == _profile.combo_clip:
		_combo_done = true


## The camera at the push for the current time: full-body 3/4 into the hero
## frame while the load is held.
func _frame_camera(_delta: float) -> void:
	var push := 1.0 if _stage == Stage.RESULTS else smoothstep(_profile.camera_push_start, _profile.camera_push_end, _time)
	var frame := _actor.global_transform
	var from := frame * _profile.camera_start
	var to := frame * _profile.camera_finish
	var look := lerpf(_profile.look_start_height, _profile.look_finish_height, push)
	_camera.fov = lerpf(_profile.fov_start, _profile.fov_finish, push)
	var at := from.lerp(to, push)
	_camera.look_at_from_position(at, _actor.global_position + Vector3.UP * look, Vector3.UP)


func _sample_trail(step: float) -> void:
	var pivot := _actor.display_pivot().global_transform
	var hilt := pivot * Vector3(0.0, 0.0, _hilt)
	var tip := pivot * Vector3(0.0, 0.0, _tip)
	var speed := tip.distance_to(_previous_tip) / maxf(step, 1e-6) if step > 0.0 else 0.0
	_previous_tip = tip
	_trail.add_sample(hilt, tip, _trail_potential(), speed, TRAIL_MIN_SPEED)


func _trail_potential() -> float:
	if _stage != Stage.CINEMATIC:
		return 0.0
	if _time >= _profile.quick_cut_1_time and _time < _profile.quick_cut_2_end_time:
		return QUICK_CUT_POTENTIAL
	return 0.0


func _blade_tip() -> Vector3:
	return _actor.display_pivot().global_transform * Vector3(0.0, 0.0, _tip)


func _screen(world: Vector3) -> Vector2:
	if _camera == null or not _camera.is_inside_tree():
		return Vector2.ZERO
	return _camera.unproject_position(world)
