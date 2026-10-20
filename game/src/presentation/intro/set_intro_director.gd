class_name SetIntroDirector
extends Node3D

## The once-per-set fighter introduction. Presentation-only: it never steps,
## reads, or writes the match's simulation. The clock owner keeps the tick
## driver stopped while it plays and resumes (without catching up) when it
## finishes or is skipped, so the first authoritative tick is the same with
## or without an intro.
##
## Each fighter's shot is real play, replayed: an `IntroTake` recorded by
## stepping the real simulation (the application's `IntroRehearsal`) — a step
## in from the 45° start guard, a wind-back while walking, and a cut — posed
## on an intro-only `FighterPresentation3D` exactly as the match presenter
## poses a proxy (same hilt track, rig, IK, trail). Nothing here authors a
## sword angle, so the intro cannot fall behind the combat system.
##
## Timeline (~3.1 s): first fighter's shot and card, a versus beat, second
## fighter's shot and card, then a cut back to the gameplay camera under the
## sting; the round's "Match N … FIGHT!" follows from `RoundStartDirector`.
## Only the fighter whose shot is playing is visible. The other intro figure
## and its trail stay hidden, so that sword is not in the shot.
## The gameplay HUD is hidden throughout by `MatchScreen`'s chrome policy
## (PRES-CHROME-001), never by this director. Every voiced line is captioned,
## so the intro reads with sound off. Driven by `advance(delta)` from the
## screen's frame loop, so it is exact in headless tests and has no tween to
## outlive the screen.
##
## Implements: /spec/invariants.md#pres-intro-001
## See also: /docs/concepts/presentation.md

signal card_requested(text: String)
signal finished

enum Beat { FIRST, VERSUS, SECOND, RETURN, DONE }

const BEAT_ENDS: PackedFloat64Array = [1.15, 1.55, 2.7, 3.1]
## Shot framing relative to the fighter's start: three-quarter front, far
## enough back that the whole sword stays in frame through the cut (the tip
## reaches ~1.9 m forward in Long Guard), at chest height, looking slightly
## down at the fighter as they step in.
const SHOT_DISTANCE := 3.6
const SHOT_SIDE := 1.5
const SHOT_HEIGHT := 1.55
const LOOK_HEIGHT := 1.0
const SHOT_FOV := 40.0

var _audio: AudioDirector
var _announcer: AnnouncerKit
var _kits: DuelKits
var _combatants: Array[CombatantPresentationKit] = []
var _rows: Array[PresentationFighter] = []
var _takes: Array[IntroTake] = []
var _proxies: Array[Node3D] = []
var _figures: Array[FighterPresentation3D] = []
var _trails: Array[SwordTrail3D] = []
var _camera: Camera3D
var _restore_camera: Camera3D
var _time: float = 0.0
var _beat: Beat = Beat.FIRST
var _entered: int = -1
var _done: bool = false


## `takes[slot]` is that fighter's recorded cut; a missing or empty take
## holds the fighter in the start guard of `first`.
static func create(kits: DuelKits, first: PresentationSnapshot, audio: AudioDirector, proxies: Array[Node3D], gameplay_camera: Camera3D, takes: Array[IntroTake] = []) -> SetIntroDirector:
	var director := SetIntroDirector.new()
	director.name = "SetIntro"
	director._audio = audio
	director._kits = kits
	director._announcer = kits.match_loadout.announcer if kits.match_loadout != null else AnnouncerKit.new()
	director._restore_camera = gameplay_camera
	director._proxies = proxies
	for slot in 2:
		director._combatants.append(kits.combatant(slot))
		director._rows.append(first.fighter(slot))
		var recorded := takes[slot] if slot < takes.size() and takes[slot] != null else IntroTake.new()
		if recorded.is_empty():
			var still: Array[PresentationSnapshot] = [first]
			recorded = IntroTake.of(still)
		director._takes.append(recorded)
	return director


func _ready() -> void:
	for proxy in _proxies:
		proxy.visible = false
	for slot in 2:
		var row := _rows[slot]
		var body := FighterPresentation3D.create(slot, row.side, _combatants[slot], row.push_radius, row.combatant_spec)
		body.name = "IntroFigure%d" % slot
		body.set_charge_indicator(false)
		add_child(body)
		_figures.append(body)
		var ribbon := SwordTrail3D.create(body.blade_color(), _kits.weapon.trail_samples)
		ribbon.set_percussion_fraction(ContactMechanics.percussion_fraction(row.weapon_definition))
		add_child(ribbon)
		_trails.append(ribbon)
		_perform(slot, 0.0, 0.0)
	_camera = Camera3D.new()
	_camera.name = "IntroCamera"
	_camera.fov = SHOT_FOV
	add_child(_camera)
	_camera.make_current()
	_show_shot(0)


func advance(delta: float) -> void:
	if _done:
		return
	_time += maxf(delta, 0.0)
	_beat = _beat_at(_time)
	if _beat == Beat.DONE:
		finish()
		return
	if int(_beat) != _entered:
		_entered = int(_beat)
		_enter(_beat)
	if _beat == Beat.FIRST or _beat == Beat.SECOND:
		var slot := 0 if _beat == Beat.FIRST else 1
		_perform(slot, _time - shot_start(slot), delta)
		_aim(slot)


## When `slot`'s shot begins on the intro clock.
static func shot_start(slot: int) -> float:
	return 0.0 if slot == 0 else BEAT_ENDS[1]


## Pose `slot`'s figure `seconds` into its take, interpolated between the two
## recorded ticks around it — the match presenter's own interpolation.
func _perform(slot: int, seconds: float, delta: float) -> void:
	var recorded := _takes[slot]
	var index := recorded.index_at(seconds)
	var weight := recorded.blend_at(seconds)
	var from := recorded.frames[index].fighter(slot)
	var to := recorded.frames[mini(index + 1, recorded.frames.size() - 1)].fighter(slot)
	var world := ArenaTransform.to_world(lerpf(from.x, to.x, weight), lerpf(from.y, to.y, weight))
	var body := _figures[slot]
	body.apply_pose(world, lerp_angle(from.facing, to.facing, weight), lerpf(from.weapon_angle, to.weapon_angle, weight), to, delta)
	var blade := body.trail_points()
	_trails[slot].add_sample(blade[0], blade[1], to.swing_potential, to.blade_speed, _kits.weapon.trail_min_speed)
	_trails[slot].advance(delta)


## Skip or end: restore the gameplay view exactly as it was. Idempotent.
func finish() -> void:
	if _done:
		return
	_done = true
	_beat = Beat.DONE
	for proxy in _proxies:
		if is_instance_valid(proxy):
			proxy.visible = true
	if _restore_camera != null and is_instance_valid(_restore_camera):
		_restore_camera.make_current()
	card_requested.emit("")
	finished.emit()
	queue_free()


func is_done() -> bool:
	return _done


func beat() -> Beat:
	return _beat


## The intro-only figure for `slot` (never the match proxy).
func figure(slot: int) -> FighterPresentation3D:
	return _figures[slot]


func take(slot: int) -> IntroTake:
	return _takes[slot]


static func _beat_at(time: float) -> Beat:
	for index in BEAT_ENDS.size():
		if time < BEAT_ENDS[index]:
			return index as Beat
	return Beat.DONE


func _enter(beat_now: Beat) -> void:
	match beat_now:
		Beat.FIRST, Beat.SECOND:
			var slot := 0 if beat_now == Beat.FIRST else 1
			var intro := _combatants[slot].intro()
			_show_shot(slot)
			_trails[slot].clear_trail()
			_frame_shot(slot)
			card_requested.emit(intro.display_name if intro != null else "")
			if intro != null:
				_audio.play_voice(intro.line(_combatants[slot].voice()), intro.spoken())
			## Under the name, not instead of it. A missing howl stays silent.
			_audio.play_character_call(_combatants[slot].fighter.character_call)
		Beat.VERSUS:
			card_requested.emit(_announcer.versus_caption)
			_audio.play_voice(_announcer.versus, "")
		Beat.RETURN:
			## Back to the arena with the fighters in their starting guards; the
			## round's own "Match N … FIGHT!" (RoundStartDirector) follows.
			if _restore_camera != null and is_instance_valid(_restore_camera):
				_restore_camera.make_current()
			for proxy in _proxies:
				proxy.visible = true
			for node in _figures:
				node.visible = false
			for ribbon in _trails:
				ribbon.visible = false
			card_requested.emit("")
			_audio.play_sting(_announcer.sting)


## One fighter per shot. The other figure's sword stays out of the frame.
func _show_shot(slot: int) -> void:
	for index in _figures.size():
		var on := index == slot
		_figures[index].visible = on
		_trails[index].visible = on


## Place the shot's camera from where the fighter starts the take: three
## quarters in front, on their sword side.
func _frame_shot(slot: int) -> void:
	var row := _takes[slot].frames[0].fighter(slot)
	var at := ArenaTransform.to_world(row.x, row.y)
	var forward := Vector3(cos(row.facing), 0.0, -sin(row.facing))
	var right := forward.cross(Vector3.UP)
	_camera.position = at + forward * SHOT_DISTANCE + right * SHOT_SIDE + Vector3.UP * SHOT_HEIGHT
	_aim(slot)
	_camera.make_current()


## Keep the fighter centred as they step in.
func _aim(slot: int) -> void:
	_camera.look_at(_figures[slot].global_position + Vector3.UP * LOOK_HEIGHT, Vector3.UP)
