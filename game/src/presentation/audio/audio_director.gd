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

var last_cue: StringName = &""
var _spatial: Array[AudioStreamPlayer3D] = []
var _flat: Array[AudioStreamPlayer] = []
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


func stop_all() -> void:
	for voice in _spatial:
		voice.stop()
	for voice in _flat:
		voice.stop()
	_music.stop()
