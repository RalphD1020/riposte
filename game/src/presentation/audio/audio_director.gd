class_name AudioDirector
extends Node

## Pooled match audio. Spatial voices for blade and body contact play on the
## Combat bus, flat voices for round stings on SFX, menu/HUD cues on UI, the
## announcer on Voice, one music voice loops the arena ambience on Music, and
## one sting voice (victory fanfare) plays on Music beside it. Cues come from
## kits; a missing cue is silent and never holds anything up — a voiced line
## still asks for its caption. Doppler is off: the camera moves, sounds should
## not wobble.
##
## Loop families: the one-shot paths (`play`, `play_flat`, `play_ui`,
## `play_voice`, `play_sting`) take streams that do not loop; a looping stream
## belongs only to a held voice with an owner that releases it (`hold_tension`
## / `release_tension`, `hold_bind` / `release_bind`) or to `play_music`.
## `stop_all` silences every family.
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
## A held scrape at level 0 is this quiet (linear gain): kept, but inaudible.
const SCRAPE_SILENT := 0.0001

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
## The contact each held scrape belongs to.
var _bind_key := PackedInt32Array([0, 0])
var _voice: AudioStreamPlayer
var _music: AudioStreamPlayer
var _sting: AudioStreamPlayer
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
	## One line and one sting at a time: a second request replaces the first
	## rather than layering over it.
	_voice = _flat_voice(AudioBuses.VOICE)
	_voice.max_polyphony = 1
	_music = _flat_voice(AudioBuses.MUSIC)
	_music.volume_db = MUSIC_VOLUME_DB
	_sting = _flat_voice(AudioBuses.MUSIC)
	_sting.max_polyphony = 1


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


## A musical sting (the victory fanfare) on its own Music voice, alongside
## whatever is being said; never stolen by the SFX pool.
func play_sting(stream: AudioStream) -> bool:
	if stream == null:
		return false
	_start(_sting, stream, 0.0)
	return true


func is_voice_playing() -> bool:
	return _voice.playing


func is_sting_playing() -> bool:
	return _sting.playing


## True while any voice of any family is sounding (tests, teardown checks).
func is_any_playing() -> bool:
	for pool: Array in [_spatial, _flat, _ui, _tension, _bind]:
		for player: Variant in pool:
			if player.playing:
				return true
	return _voice.playing or _music.playing or _sting.playing


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


## The sustained scrape of held swords, on its own voice per pair slot for as
## long as one contact lasts (`ContactScrape`). `level` in [0, 1] is its
## loudness — silent at 0, so a blade pressed still keeps its take without a
## sound. A different `key` (a new contact) starts a new take; the same key
## never re-triggers.
func hold_bind(slot: int, kit: PresentationKit, world: Vector3, level: float, key: int) -> bool:
	if kit == null or not kit.has_audio(PresentationKit.CUE_BIND):
		return false
	var voice := _bind[slot]
	voice.position = world
	voice.volume_db = linear_to_db(maxf(clampf(level, 0.0, 1.0), SCRAPE_SILENT))
	if voice.playing and _bind_key[slot] != key:
		voice.stop()
	_bind_key[slot] = key
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


## The held scrape's current loudness (dB) and the contact it belongs to.
func bind_volume_db(slot: int) -> float:
	return _bind[slot].volume_db


func bind_key(slot: int) -> int:
	return _bind_key[slot]


func stop_all() -> void:
	for pool: Array in [_spatial, _flat, _ui, _tension, _bind]:
		for player: Variant in pool:
			player.stop()
	_voice.stop()
	_music.stop()
	_sting.stop()


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
