class_name AudioDirector
extends Node

## Pooled match audio. Spatial voices for blade and body contact play on the
## Combat bus, flat voices for round stings on SFX, menu/HUD cues on UI, the
## announcer on Voice, and one music voice loops the arena ambience on Music.
## Cues come from kits; a missing cue is silent. Doppler is off: the camera
## moves, sounds should not wobble.
##
## Variety without nondeterminism: a cue with several takes picks one from a
## key the caller derives from the event (tick, actor), so a replay hears the
## same takes in the same order. Layers declared on the kit play from the
## same event with the same key.
##
## See also: /docs/concepts/presentation.md

## Every voiced line also asks for a caption, so nothing is conveyed by sound
## alone (UX-001).
signal caption_requested(text: String, seconds: float)

const SPATIAL_VOICES := 12
const FLAT_VOICES := 2
const UI_VOICES := 2
const MUSIC_VOLUME_DB := -6.0
## Distance (m) at which spatial voices start to attenuate: the whole arena
## stays audible.
const SPATIAL_UNIT_SIZE := 8.0
## Layers sit under the primary so the transient still leads.
const LAYER_VOLUME_DB := -3.0
const CAPTION_MIN_SECONDS := 0.9
const HISTORY_LIMIT := 64

## The wind-back tension layer. Pitch and level ride the earned wind-back from
## the resting blade to the most that is physically reachable; because `charge`
## already saturates there, the plateau at the top is the simulation's, not an
## authored cap (COMBAT-009).
const TENSION_PITCH_REST := 0.85
const TENSION_PITCH_FULL := 1.35
const TENSION_DB_REST := -24.0
const TENSION_DB_FULL := -7.0

var last_cue: StringName = &""
## Every cue started, with the stream chosen, in order. Tests read it to prove
## that the same events always pick the same takes.
var history: Array[AudioStream] = []
var _spatial: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
var _ui: Array[AudioStreamPlayer] = []
## One held voice per fighter, kept out of the pool: a wind-back lasts many
## frames and must not be stolen by the next blade clash.
var _tension: Array[AudioStreamPlayer3D] = []
var _bind: Array[AudioStreamPlayer3D] = []
var _voice: AudioStreamPlayer
var _music: AudioStreamPlayer
var _next_spatial: int = 0
var _next_flat: int = 0
var _next_ui: int = 0


func _init() -> void:
	name = "Audio"
	for _i in SPATIAL_VOICES:
		_spatial.append(_spatial_voice(AudioBuses.COMBAT))
	for _i in FLAT_VOICES:
		_flat.append(_flat_voice(AudioBuses.SFX))
	for _i in UI_VOICES:
		_ui.append(_flat_voice(AudioBuses.UI))
	for _i in 2:
		_tension.append(_spatial_voice(AudioBuses.COMBAT))
		_bind.append(_spatial_voice(AudioBuses.COMBAT))
	_voice = _flat_voice(AudioBuses.VOICE)
	_music = _flat_voice(AudioBuses.MUSIC)
	_music.volume_db = MUSIC_VOLUME_DB


## Loop the kit's ambience; a kit without music stays silent. Must be called
## inside the tree (the presenter does it on ready).
func play_music(kit: PresentationKit) -> bool:
	if kit == null or not kit.has_audio(PresentationKit.CUE_MUSIC) or not is_inside_tree():
		return false
	var stream := kit.stream_for(PresentationKit.CUE_MUSIC)
	if _music.stream != stream:
		_music.stream = stream
	if not _music.playing:
		_music.play()
	return true


func is_music_playing() -> bool:
	return _music.playing


func music_stream() -> AudioStream:
	return _music.stream


## A spatial combat cue plus any layers the kit declares for it.
func play(cue: StringName, kit: PresentationKit, world: Vector3, volume_db: float = 0.0, pitch: float = 1.0, key: int = 0) -> bool:
	if kit == null or not kit.has_audio(cue):
		return false
	_start_spatial(kit.stream_for(cue, key), world, volume_db, pitch)
	for layer in kit.layers_for(cue):
		_start_spatial(kit.stream_for(layer, key), world, volume_db + LAYER_VOLUME_DB, pitch)
	last_cue = cue
	return true


func play_flat(cue: StringName, kit: PresentationKit, volume_db: float = 0.0, key: int = 0) -> bool:
	if kit == null or not kit.has_audio(cue):
		return false
	var voice := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	_start(voice, kit.stream_for(cue, key), volume_db)
	last_cue = cue
	return true


func play_ui(cue: StringName, kit: PresentationKit, key: int = 0) -> bool:
	if kit == null or not kit.has_audio(cue):
		return false
	var voice := _ui[_next_ui]
	_next_ui = (_next_ui + 1) % _ui.size()
	_start(voice, kit.stream_for(cue, key), 0.0)
	last_cue = cue
	return true


## One announcer line. The caption is requested even when the line is
## missing or muted, so the moment still reads.
func play_voice(stream: AudioStream, caption: String) -> bool:
	var seconds := CAPTION_MIN_SECONDS
	if stream != null:
		seconds = maxf(seconds, stream.get_length())
	if caption != "":
		caption_requested.emit(caption, seconds)
	if stream == null:
		return false
	_start(_voice, stream, 0.0)
	return true


## A flat musical/metal stinger on SFX, alongside whatever is being said.
func play_sting(stream: AudioStream) -> bool:
	if stream == null:
		return false
	var voice := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	_start(voice, stream, 0.0)
	return true


func is_voice_playing() -> bool:
	return _voice.playing


## Hold or update one fighter's wind-back tension. Idempotent per frame: the
## voice is started once and then simply retuned, so the layer tightens
## continuously instead of retriggering.
func hold_tension(slot: int, kit: PresentationKit, world: Vector3, charge: float) -> bool:
	if kit == null or not kit.has_audio(PresentationKit.CUE_CHARGE):
		return false
	var voice := _tension[slot]
	var earned := clampf(charge, 0.0, 1.0)
	voice.position = world
	voice.pitch_scale = lerpf(TENSION_PITCH_REST, TENSION_PITCH_FULL, earned)
	voice.volume_db = lerpf(TENSION_DB_REST, TENSION_DB_FULL, earned)
	if not voice.playing:
		voice.stream = kit.stream_for(PresentationKit.CUE_CHARGE, slot)
		voice.play()
		last_cue = PresentationKit.CUE_CHARGE
	return true


## Let the tension go. Called whenever the blade stops winding back, including
## on release, cancel, death, and round reset, so a held layer can never
## outlive the swing that earned it.
func release_tension(slot: int) -> void:
	_tension[slot].stop()


func is_tension_held(slot: int) -> bool:
	return _tension[slot].playing


func tension_pitch(slot: int) -> float:
	return _tension[slot].pitch_scale


## The sustained grind of pinned blades, held on its own voice per fighter
## pair slot for as long as the bind lasts. `pressure` in [0, 1] rides gain.
func hold_bind(slot: int, kit: PresentationKit, world: Vector3, pressure: float, key: int) -> bool:
	if kit == null or not kit.has_audio(PresentationKit.CUE_BIND):
		return false
	var voice := _bind[slot]
	voice.position = world
	voice.volume_db = lerpf(TENSION_DB_REST, 0.0, clampf(pressure, 0.0, 1.0))
	if not voice.playing:
		voice.stream = kit.stream_for(PresentationKit.CUE_BIND, key)
		voice.play()
		_remember(voice.stream)
		last_cue = PresentationKit.CUE_BIND
	return true


func release_bind(slot: int) -> void:
	_bind[slot].stop()


func is_bind_held(slot: int) -> bool:
	return _bind[slot].playing


func stop_all() -> void:
	for pool: Array in [_spatial, _flat, _ui, _tension, _bind]:
		for player: Variant in pool:
			player.stop()
	_voice.stop()
	_music.stop()


func _start_spatial(stream: AudioStream, world: Vector3, volume_db: float, pitch: float) -> void:
	var voice := _spatial[_next_spatial]
	_next_spatial = (_next_spatial + 1) % _spatial.size()
	voice.position = world
	voice.pitch_scale = pitch
	_start(voice, stream, volume_db)


func _start(player: Node, stream: AudioStream, volume_db: float) -> void:
	player.set("stream", stream)
	player.set("volume_db", volume_db)
	player.call("play")
	_remember(stream)


func _remember(stream: AudioStream) -> void:
	history.append(stream)
	if history.size() > HISTORY_LIMIT:
		history.remove_at(0)


func _spatial_voice(bus: StringName) -> AudioStreamPlayer3D:
	var voice := AudioStreamPlayer3D.new()
	voice.bus = bus
	voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
	voice.unit_size = SPATIAL_UNIT_SIZE
	add_child(voice)
	return voice


func _flat_voice(bus: StringName) -> AudioStreamPlayer:
	var voice := AudioStreamPlayer.new()
	voice.bus = bus
	add_child(voice)
	return voice
