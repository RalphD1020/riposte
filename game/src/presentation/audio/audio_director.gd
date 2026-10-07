class_name AudioDirector
extends Node

## Pooled match audio. Spatial voices for blade and body contact and flat
## voices for round stings play on the SFX bus; one music voice loops the
## arena ambience on the Music bus. Cues come from kits; a missing cue is
## silent. Doppler is off: the camera moves, sounds should not wobble.
##
## See also: /docs/concepts/presentation.md

const SPATIAL_VOICES := 8
const FLAT_VOICES := 2
const MUSIC_VOLUME_DB := -6.0
## Distance (m) at which spatial voices start to attenuate: the whole arena
## stays audible.
const SPATIAL_UNIT_SIZE := 8.0

## The wind-back tension layer. Pitch and level ride the earned wind-back from
## the resting blade to the most that is physically reachable; because `charge`
## already saturates there, the plateau at the top is the simulation's, not an
## authored cap (COMBAT-009).
const TENSION_PITCH_REST := 0.85
const TENSION_PITCH_FULL := 1.35
const TENSION_DB_REST := -24.0
const TENSION_DB_FULL := -7.0

var last_cue: StringName = &""
var _spatial: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
## One held voice per fighter, kept out of the pool: a wind-back lasts many
## frames and must not be stolen by the next blade clash.
var _tension: Array[AudioStreamPlayer3D] = []
var _music: AudioStreamPlayer
var _next_spatial: int = 0
var _next_flat: int = 0


func _init() -> void:
	name = "Audio"
	for _i in SPATIAL_VOICES:
		var voice := AudioStreamPlayer3D.new()
		voice.bus = AudioBuses.SFX
		voice.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		voice.unit_size = SPATIAL_UNIT_SIZE
		add_child(voice)
		_spatial.append(voice)
	for _i in FLAT_VOICES:
		var flat := AudioStreamPlayer.new()
		flat.bus = AudioBuses.SFX
		add_child(flat)
		_flat.append(flat)
	for _i in 2:
		var held := AudioStreamPlayer3D.new()
		held.bus = AudioBuses.SFX
		held.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED
		held.unit_size = SPATIAL_UNIT_SIZE
		add_child(held)
		_tension.append(held)
	_music = AudioStreamPlayer.new()
	_music.bus = AudioBuses.MUSIC
	_music.volume_db = MUSIC_VOLUME_DB
	add_child(_music)


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


func play(cue: StringName, kit: PresentationKit, world: Vector3, volume_db: float = 0.0, pitch: float = 1.0) -> bool:
	if kit == null or not kit.has_audio(cue):
		return false
	var voice := _spatial[_next_spatial]
	_next_spatial = (_next_spatial + 1) % _spatial.size()
	voice.stream = kit.stream_for(cue)
	voice.position = world
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()
	last_cue = cue
	return true


func play_flat(cue: StringName, kit: PresentationKit, volume_db: float = 0.0) -> bool:
	if kit == null or not kit.has_audio(cue):
		return false
	var voice := _flat[_next_flat]
	_next_flat = (_next_flat + 1) % _flat.size()
	voice.stream = kit.stream_for(cue)
	voice.volume_db = volume_db
	voice.play()
	last_cue = cue
	return true


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
		voice.stream = kit.stream_for(PresentationKit.CUE_CHARGE)
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


func stop_all() -> void:
	for voice in _spatial:
		voice.stop()
	for voice in _flat:
		voice.stop()
	for voice in _tension:
		voice.stop()
	_music.stop()
