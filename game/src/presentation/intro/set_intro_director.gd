class_name SetIntroDirector
extends Node3D

## The once-per-set fighter introduction. Presentation-only: it never steps,
## reads, or writes the simulation. The clock owner keeps the tick driver
## stopped while it plays and resumes (without catching up) when it finishes
## or is skipped, so the first authoritative tick is the same with or
## without an intro.
##
## Timeline (~2.6 s): first fighter close-up and card, a versus beat, second
## fighter close-up and card, then a cut back to the gameplay camera with
## the "duel" call. Every voiced line is captioned, so the intro reads with
## sound off. Driven by `advance(delta)` from the screen's frame loop, so it
## is exact in headless tests and has no tween to outlive the screen.
##
## Implements: /spec/invariants.md#pres-intro-001
## See also: /docs/concepts/presentation.md

signal card_requested(text: String)
signal finished

enum Beat { FIRST, VERSUS, SECOND, DUEL, DONE }

const BEAT_ENDS: PackedFloat64Array = [0.75, 1.15, 1.9, 2.6]
## Close-up framing relative to the fighter: in front, a little to the side,
## at chest height, looking slightly down.
const CLOSE_DISTANCE := 2.3
const CLOSE_SIDE := 0.7
const CLOSE_HEIGHT := 1.45
const LOOK_HEIGHT := 1.05
const CLOSE_FOV := 38.0

var _audio: AudioDirector
var _announcer: AnnouncerKit
var _combatants: Array[CombatantPresentationKit] = []
var _rows: Array[PresentationFighter] = []
var _proxies: Array[Node3D] = []
var _showcases: Array[FighterShowcasePresenter] = []
var _camera: Camera3D
var _restore_camera: Camera3D
var _time: float = 0.0
var _beat: Beat = Beat.FIRST
var _entered: int = -1
var _done: bool = false


static func create(kits: DuelKits, first: PresentationSnapshot, audio: AudioDirector, proxies: Array[Node3D], gameplay_camera: Camera3D) -> SetIntroDirector:
	var director := SetIntroDirector.new()
	director.name = "SetIntro"
	director._audio = audio
	director._announcer = kits.match_loadout.announcer if kits.match_loadout != null else AnnouncerKit.new()
	director._restore_camera = gameplay_camera
	director._proxies = proxies
	for slot in 2:
		director._combatants.append(kits.combatant(slot))
		director._rows.append(first.fighter(slot))
	return director


func _ready() -> void:
	for proxy in _proxies:
		proxy.visible = false
	for slot in 2:
		var row := _rows[slot]
		var figure := FighterShowcasePresenter.create(_combatants[slot], row.side, _combatants[slot].intro(), row.body_radius, row.hilt_radius, row.tip_radius)
		figure.position = ArenaTransform.to_world(row.x, row.y)
		figure.rotation.y = ArenaTransform.yaw(row.facing)
		add_child(figure)
		_showcases.append(figure)
	_camera = Camera3D.new()
	_camera.name = "IntroCamera"
	_camera.fov = CLOSE_FOV
	add_child(_camera)
	_camera.make_current()


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
		var start := 0.0 if slot == 0 else BEAT_ENDS[1]
		_showcases[slot].flourish((_time - start) / (BEAT_ENDS[int(_beat)] - start))


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


func showcase(slot: int) -> FighterShowcasePresenter:
	return _showcases[slot]


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
			_frame_close_up(slot)
			card_requested.emit(intro.display_name if intro != null else "")
			if intro != null:
				_audio.play_voice(intro.line_for(slot, _combatants[slot].voice()), intro.spoken_for(slot))
		Beat.VERSUS:
			card_requested.emit(_announcer.versus_caption)
			_audio.play_voice(_announcer.versus, "")
		Beat.DUEL:
			if _restore_camera != null and is_instance_valid(_restore_camera):
				_restore_camera.make_current()
			for proxy in _proxies:
				proxy.visible = true
			for showcase_node in _showcases:
				showcase_node.visible = false
			card_requested.emit(_announcer.duel_caption)
			_audio.play_sting(_announcer.sting)
			_audio.play_voice(_announcer.duel, _announcer.duel_caption)


func _frame_close_up(slot: int) -> void:
	var row := _rows[slot]
	var at := ArenaTransform.to_world(row.x, row.y)
	var forward := Vector3(cos(row.facing), 0.0, -sin(row.facing))
	var right := forward.cross(Vector3.UP)
	_camera.position = at + forward * CLOSE_DISTANCE + right * CLOSE_SIDE + Vector3.UP * CLOSE_HEIGHT
	_camera.look_at(at + Vector3.UP * LOOK_HEIGHT, Vector3.UP)
	_camera.make_current()
