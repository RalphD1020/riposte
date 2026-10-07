class_name PlaceholderAudio
extends RefCounted

## Procedural placeholder sounds for MVP-0 kits: a metallic clang per blade
## contact class, a low thud for body hits, a whoosh for swings, a rising
## tension tone for charging, a two-note round sting, and a quiet looping
## arena drone for the Music bus. Content, not runtime: replacing a sound
## means pointing the kit's cue at a real stream. Generated once (16-bit
## mono; 22.05 kHz effects, 11.025 kHz drone) and cached.
##
## See also: /docs/concepts/presentation.md

const MIX_RATE := 22050
const AMBIENT_RATE := 11025
## Every partial and the swell complete whole cycles in this loop.
const AMBIENT_SECONDS := 2.0

static var _cache: Dictionary = {}


static func cues() -> Dictionary:
	if _cache.is_empty():
		_cache = {
			PresentationKit.CUE_BLADE_LIGHT: _clang(0.12, 0.35),
			PresentationKit.CUE_BLADE_SOLID: _clang(0.2, 0.6),
			PresentationKit.CUE_BLADE_STRONG: _clang(0.32, 0.9),
			PresentationKit.CUE_BIND: _grind(),
			PresentationKit.CUE_BODY_LIGHT: _thud(0.12, 0.45),
			PresentationKit.CUE_BODY_HEAVY: _thud(0.22, 0.85),
			PresentationKit.CUE_BODY_POKE: _poke(),
			PresentationKit.CUE_BODY_THRUST: _thrust(),
			PresentationKit.CUE_CRITICAL: _critical(),
			PresentationKit.CUE_SWING: _whoosh(0.18, 0.4),
			PresentationKit.CUE_CHARGE: _tension(0.45, 0.18),
			PresentationKit.CUE_ROUND: _sting(),
			PresentationKit.CUE_MUSIC: _ambient(),
		}
	return _cache


static func _clang(duration: float, gain: float) -> AudioStreamWAV:
	var partials := [1180.0, 2690.0, 4150.0]
	return _render(duration, func(t: float, noise: float) -> float:
		var tone := 0.0
		for frequency: float in partials:
			tone += sin(TAU * frequency * t) / 3.0
		return gain * exp(-t * 22.0) * (0.8 * tone + 0.2 * noise)
	)


## A bind is blades pinned and grinding, not a clang that happens to be quiet:
## it sustains instead of decaying, so the two situations never sound alike.
static func _grind() -> AudioStreamWAV:
	return _render(0.28, func(t: float, noise: float) -> float:
		var envelope := clampf(t * 30.0, 0.0, 1.0) * clampf((0.28 - t) * 12.0, 0.0, 1.0)
		var scrape := sin(TAU * (420.0 + 90.0 * sin(TAU * 11.0 * t)) * t)
		return 0.45 * envelope * (0.45 * scrape + 0.55 * noise)
	)


static func _thud(duration: float, gain: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, noise: float) -> float:
		return gain * exp(-t * 18.0) * (0.75 * sin(TAU * (95.0 - 30.0 * t) * t) + 0.25 * noise)
	)


static func _whoosh(duration: float, gain: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, noise: float) -> float:
		var envelope := sin(PI * clampf(t / duration, 0.0, 1.0))
		return gain * envelope * noise
	)


static func _tension(duration: float, gain: float) -> AudioStreamWAV:
	return _render(duration, func(t: float, _noise: float) -> float:
		var frequency := 300.0 + 400.0 * t / duration
		return gain * sin(TAU * frequency * t) * clampf(t * 8.0, 0.0, 1.0) * (1.0 - t / duration)
	)


## A poke is a narrow, sharp contact — higher pitch than a thud, fast decay.
static func _poke() -> AudioStreamWAV:
	return _render(0.14, func(t: float, noise: float) -> float:
		return 0.55 * exp(-t * 26.0) * (0.65 * sin(TAU * 280.0 * t) + 0.35 * noise)
	)


## A thrust is a committed puncture — deeper than a poke, slightly sustained.
static func _thrust() -> AudioStreamWAV:
	return _render(0.2, func(t: float, noise: float) -> float:
		var body := sin(TAU * (140.0 - 40.0 * t) * t)
		var ring := sin(TAU * 600.0 * t) * exp(-t * 20.0)
		return 0.7 * exp(-t * 14.0) * (0.55 * body + 0.25 * ring + 0.2 * noise)
	)


static func _critical() -> AudioStreamWAV:
	return _render(0.35, func(t: float, noise: float) -> float:
		var ring := sin(TAU * 1500.0 * t) * exp(-t * 14.0)
		var body := sin(TAU * 80.0 * t) * exp(-t * 12.0)
		return 0.9 * (0.5 * ring + 0.5 * body) + 0.1 * noise * exp(-t * 30.0)
	)


static func _sting() -> AudioStreamWAV:
	return _render(0.4, func(t: float, _noise: float) -> float:
		var frequency := 660.0 if t < 0.16 else 880.0
		var local := t if t < 0.16 else t - 0.16
		return 0.35 * sin(TAU * frequency * t) * exp(-local * 9.0)
	)


static func _ambient() -> AudioStreamWAV:
	var drone := func(t: float, _noise: float) -> float:
		var swell := 0.6 + 0.4 * sin(TAU * 0.5 * t)
		return 0.12 * swell * (0.5 * sin(TAU * 55.0 * t) + 0.3 * sin(TAU * 82.5 * t) + 0.2 * sin(TAU * 110.0 * t))
	var stream := _render(AMBIENT_SECONDS, drone, AMBIENT_RATE)
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = int(AMBIENT_SECONDS * AMBIENT_RATE)
	return stream


## Render `sample(t, noise)` into a 16-bit PCM stream. Fixed-seed noise keeps
## the placeholder identical every run.
static func _render(duration: float, sample: Callable, rate: int = MIX_RATE) -> AudioStreamWAV:
	var noise := RandomNumberGenerator.new()
	noise.seed = 3
	var count := int(duration * rate)
	var data := PackedByteArray()
	data.resize(count * 2)
	for i in count:
		var value := clampf(float(sample.call(float(i) / rate, noise.randf_range(-1.0, 1.0))), -1.0, 1.0)
		data.encode_s16(i * 2, int(value * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
