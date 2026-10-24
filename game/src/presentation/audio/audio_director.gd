class_name AudioDirector
extends Node

## Pooled match audio. Spatial voices for blade and body contact play on the
## Combat bus, flat voices for round stings on SFX, menu/HUD cues on UI, two
## independently owned Voice players (the announcer and the fighter call),
## and one sting voice on Music (the match horn, or this director's victory
## sting). The menu and arena
## loops are not this director's: `RiposteApp` owns that one player and
## selects the stream. Cues come from kits; a missing cue is silent and never
## holds anything up — a voiced line still asks for its caption. Doppler is
## off: the camera moves, sounds should not wobble.
##
## Loop families: the one-shot paths (`play`, `play_flat`, `play_ui`,
## `play_voice`, `play_sting`) take streams that do not loop; a looping stream
## belongs only to a held voice with an owner that releases it (`hold_tension`
## / `release_tension`, `hold_bind` / `release_bind`) or to the app's music loop.
## `stop_all` silences every family.
##
## Variety without nondeterminism: a cue with several takes picks one from a
## key the caller derives from the event (tick, actor), so a replay hears the
## same takes in the same order. Crowd reactions increment that key per cue
## so a second eligible shot does not immediately repeat when alternatives
## exist. Layers declared on the kit play from the same event with the same
## key.
##
## See also: /docs/concepts/presentation.md

## Every voiced line also asks for a caption, so nothing is conveyed by sound
## alone (UX-001).
signal caption_requested(text: String, seconds: float)

const SPATIAL_VOICES := 12
const FLAT_VOICES := 2
const UI_VOICES := 2
## Distance (m) at which spatial voices start to attenuate: the whole arena
## stays audible.
const SPATIAL_UNIT_SIZE := 8.0
## Layers sit under the primary so the transient still leads.
const LAYER_VOLUME_DB := -3.0
## The howl sits under the announcer on the same bus, on its own player.
## The spoken line is boosted. The howl file is denser than speech, so the
## call stays well under that line.
const ANNOUNCER_GAIN_DB := 6.0
const CALL_TRIM_DB := -20.0
## The character victory sting, on this director's Music player. Under the
## announcer. The howl's trim is the call, not this cue. Listening can retune
## it; the buses stay as they are.
const VICTORY_STING_DB := -6.0
const PLAYER_ANNOUNCER := "VoiceAnnouncer"
const PLAYER_FIGHTER := "VoiceFighter"
const PLAYER_STING := "MusicSting"
## How long the match-end horn is heard, as one blast. A shorter take is
## slowed so that single play fills this hold. It is not started again.
const HORN_SECONDS := 6.0
const PLAYER_CROWD_BED := "CrowdBed"
const PLAYER_CROWD_SHOT := "CrowdShot"
const PLAYER_CROWD_CHANT := "CrowdChant"
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
var _character_call: AudioStreamPlayer
var _sting: AudioStreamPlayer
var _crowd_bed: AudioStreamPlayer
var _crowd_shot: AudioStreamPlayer
var _crowd_chant: AudioStreamPlayer
var _chant_source: AudioStream
## A non-looping name phrase. The director plays it again after the gap.
## `wolf_chant.mp3` is not marked loop; this is how it repeats.
const PHRASE_GAP_SECONDS := 1.5
var _phrase_open: bool = false
var _phrase_stream: AudioStream
var _phrase_left: float = 0.0
var _phrase_gap: float = 0.0
var _chant_fade_from: float = -8.0
var _chant_fade_left: float = 0.0
var _chant_fade_seconds: float = 0.0
## Ordinary release. A finish and the set win stop instead of fading.
const CHANT_TRIM_DB := -8.0
const CHANT_FADE_FLOOR_DB := -40.0
const CHANT_RELEASE_SECONDS := 0.4
## Next take index per crowd cue. Incremented only when that cue actually
## starts, so a replay of the same presentation sequence stays identical.
var _crowd_shot_index: Dictionary = {}
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
	## Two Voice channels, not one polyphonic player: assigning a stream on
	## the announcer must not stop the fighter call, and the reverse. Each
	## channel is still one line at a time.
	_voice = _flat_voice(AudioBuses.VOICE)
	_voice.name = PLAYER_ANNOUNCER
	_voice.max_polyphony = 1
	_character_call = _flat_voice(AudioBuses.VOICE)
	_character_call.name = PLAYER_FIGHTER
	_character_call.max_polyphony = 1
	_character_call.volume_db = CALL_TRIM_DB
	_sting = _flat_voice(AudioBuses.MUSIC)
	_sting.name = PLAYER_STING
	_sting.max_polyphony = 1
	_crowd_bed = _flat_voice(AudioBuses.CROWD)
	_crowd_bed.name = PLAYER_CROWD_BED
	_crowd_shot = _flat_voice(AudioBuses.CROWD)
	_crowd_shot.name = PLAYER_CROWD_SHOT
	_crowd_chant = _flat_voice(AudioBuses.CROWD)
	_crowd_chant.name = PLAYER_CROWD_CHANT
	_crowd_chant.volume_db = CHANT_TRIM_DB


func is_character_call_playing() -> bool:
	return _character_call.playing


func character_call_stream() -> AudioStream:
	return _character_call.stream


func announcer_stream() -> AudioStream:
	return _voice.stream


func is_crowd_bed_playing() -> bool:
	return _crowd_bed.playing


func crowd_bed_stream() -> AudioStream:
	return _crowd_bed.stream


func crowd_bed_volume_db() -> float:
	return _crowd_bed.volume_db


func set_crowd_bed_volume_db(volume_db: float) -> void:
	_crowd_bed.volume_db = volume_db


func crowd_shot_stream() -> AudioStream:
	return _crowd_shot.stream


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
	_start(_voice, stream, ANNOUNCER_GAIN_DB)
	return true


## The character howl, under the announcer. A missing take is silent.
func play_character_call(stream: AudioStream) -> bool:
	if stream == null:
		return false
	_start(_character_call, stream, CALL_TRIM_DB)
	return true


## Loop the crowd bed. A second call with the same stream does not restart it.
func play_crowd_bed(stream: AudioStream) -> bool:
	if stream == null or not is_inside_tree():
		return false
	if _crowd_bed.stream != stream:
		_crowd_bed.stream = stream
	if not _crowd_bed.playing:
		_crowd_bed.play()
		_remember(stream)
	return true


## One crowd reaction. A new reaction replaces one that is still playing,
## which is how the cooldown's choice stays a single voice.
func play_crowd_shot(stream: AudioStream) -> bool:
	if stream == null:
		return false
	_start(_crowd_shot, stream, 0.0)
	return true


## A kit cue's next take. The key increments per cue so two eligible shots
## of the same class do not immediately repeat when the kit has more than
## one take. One take is still that one take.
## True when this stream was imported as a loop. A one-shot is not made
## loopable here: `wolf_chant.mp3` is a shout with a quiet tail, and flipping
## its loop flag would repeat that tail. The set win still plays it once.
func accepts_crowd_chant(stream: AudioStream) -> bool:
	return stream is AudioStreamMP3 and (stream as AudioStreamMP3).loop


## One looping name. The same source, already playing, does not restart.
## A different source replaces it. A stream that is not a loop does not play
## and does not disturb whatever is already playing; the caller stops that.
func play_crowd_chant(stream: AudioStream) -> bool:
	if not accepts_crowd_chant(stream):
		return false
	if _crowd_chant.playing and _chant_source == stream:
		_chant_fade_left = 0.0
		_crowd_chant.volume_db = CHANT_TRIM_DB
		return false
	_chant_fade_left = 0.0
	_chant_source = stream
	var playing := stream.duplicate() as AudioStream
	_start(_crowd_chant, playing, CHANT_TRIM_DB)
	return true


## Fade the name out, then stop. A fade already running is left alone.
## A silent player is left silent.
func release_crowd_chant(seconds: float) -> void:
	if not _crowd_chant.playing:
		_chant_source = null
		_chant_fade_left = 0.0
		return
	if seconds <= 0.0:
		_phrase_open = false
		_phrase_stream = null
		_phrase_left = 0.0
		_phrase_gap = 0.0
		return
	if seconds <= 0.0:
		stop_crowd_chant()
		return
	if _chant_fade_left > 0.0:
		return
	_chant_fade_from = _crowd_chant.volume_db
	_chant_fade_seconds = seconds
	_chant_fade_left = seconds


## One play of a non-looping name. The same open phrase does not stack.
## After it ends, `advance_crowd_chant` waits `PHRASE_GAP_SECONDS` and plays it again.
## Phrase length and the gap are both frame-delta seconds. `CrowdDirector.CHANT_HOLD_TICKS`
## is a separate simulation-tick hold. It does not time this gap.
## A stream with no length does not open a phrase, so a bad import cannot restart forever.
func play_name_phrase(stream: AudioStream) -> bool:
	if stream == null or stream.get_length() <= 0.0:
		return false
	if _phrase_open and _phrase_stream == stream:
		return false
	_phrase_open = true
	_phrase_stream = stream
	_phrase_gap = 0.0
	return _begin_phrase()


func _begin_phrase() -> bool:
	var playing := _phrase_stream.duplicate() as AudioStream
	var length := playing.get_length() if playing != null else 0.0
	if length <= 0.0:
		_phrase_open = false
		_phrase_stream = null
		return false
	_chant_source = _phrase_stream
	_start(_crowd_chant, playing, CHANT_TRIM_DB)
	_phrase_left = length
	return true


func advance_crowd_chant(delta: float) -> void:
	var step := maxf(delta, 0.0)
	if _phrase_open and _phrase_stream != null and _chant_fade_left <= 0.0:
		if _crowd_chant.playing:
			_phrase_left = maxf(_phrase_left - step, 0.0)
			if _phrase_left <= 0.0:
				_crowd_chant.stop()
				_crowd_chant.volume_db = CHANT_TRIM_DB
				_phrase_gap = PHRASE_GAP_SECONDS
		elif _phrase_gap > 0.0:
			_phrase_gap = maxf(_phrase_gap - step, 0.0)
			if _phrase_gap <= 0.0:
				_begin_phrase()
	if _chant_fade_seconds > 0.0:
		_chant_fade_left = maxf(_chant_fade_left - step, 0.0)
		var along := 1.0 - _chant_fade_left / _chant_fade_seconds
		_crowd_chant.volume_db = lerpf(_chant_fade_from, CHANT_FADE_FLOOR_DB, clampf(along, 0.0, 1.0))
		if _chant_fade_left <= 0.0:
			stop_crowd_chant()


func stop_crowd_chant() -> void:
	_chant_source = null
	_chant_fade_left = 0.0
	_crowd_chant.stop()
	_crowd_chant.volume_db = CHANT_TRIM_DB
	_phrase_open = false
	_phrase_stream = null
	_phrase_left = 0.0
	_phrase_gap = 0.0


func is_crowd_chant_playing() -> bool:
	return _crowd_chant.playing


func crowd_chant_volume_db() -> float:
	return _crowd_chant.volume_db


func play_crowd_cue(kit: PresentationKit, cue: StringName) -> bool:
	if kit == null or not kit.has_audio(cue):
		return false
	var index := int(_crowd_shot_index.get(cue, 0))
	var stream := kit.stream_for(cue, index)
	if stream == null:
		return false
	_crowd_shot_index[cue] = index + 1
	return play_crowd_shot(stream)


## The winner's one-shot, under the announcer. A null or looping stream is
## refused. The match horn uses `play_match_horn`; the intro sting uses
## `play_sting`.
func play_victory_sting(stream: AudioStream) -> bool:
	if stream == null or _loops(stream):
		return false
	_sting.pitch_scale = 1.0
	_start(_sting, stream, VICTORY_STING_DB)
	return true


## A one-shot sting at its authored speed. The match horn uses `play_match_horn`.
func play_sting(stream: AudioStream) -> bool:
	if stream == null:
		return false
	_sting.pitch_scale = 1.0
	_start(_sting, stream, 0.0)
	return true


## The set-winning horn, once, stretched so the take lasts `HORN_SECONDS`.
func play_match_horn(stream: AudioStream) -> bool:
	if stream == null:
		return false
	var length := stream.get_length()
	_sting.pitch_scale = length / HORN_SECONDS if length > 0.0 and length < HORN_SECONDS else 1.0
	_start(_sting, stream, 0.0)
	return true


func stop_sting() -> void:
	_sting.pitch_scale = 1.0
	_sting.stop()


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
	return _voice.playing or _character_call.playing or _sting.playing or _crowd_bed.playing or _crowd_shot.playing or _crowd_chant.playing


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
	_character_call.stop()
	_sting.stop()
	_crowd_bed.stop()
	_crowd_shot.stop()


func _start_spatial(stream: AudioStream, world: Vector3, volume_db: float, pitch: float) -> void:
	_crowd_chant.stop()
	var voice := _spatial[_next_spatial]
	_next_spatial = (_next_spatial + 1) % _spatial.size()
	voice.position = world
	voice.pitch_scale = pitch
	_start(voice, stream, volume_db)


func _loops(stream: AudioStream) -> bool:
	if stream is AudioStreamWAV:
		return (stream as AudioStreamWAV).loop_mode != AudioStreamWAV.LOOP_DISABLED
	var looping: Variant = stream.get("loop")
	return looping == null or bool(looping)


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
