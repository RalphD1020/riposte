class_name SeededRng
extends RefCounted

## Deterministic named random stream. The only wrapper around Godot's
## RandomNumberGenerator (PCG32: integer-only state, identical on every
## platform). The duel physics itself uses no randomness; consumers are
## decision makers such as the CPU controller.
##
## Implements: /spec/invariants.md#sim-rng-001
## See also: /docs/concepts/simulation.md

const STREAM_CPU_SLOT_0 := 1
const STREAM_CPU_SLOT_1 := 2
const _SEED_MASK := 0x7fffffff
const _STREAM_PRIME := 1000003

var stream: int = 0
var _rng := RandomNumberGenerator.new()


static func create(seed_value: int, stream_id: int) -> SeededRng:
	var rng := SeededRng.new()
	rng.stream = stream_id
	rng._rng.seed = (seed_value & _SEED_MASK) * _STREAM_PRIME + stream_id
	return rng


static func cpu_stream(slot: int) -> int:
	return STREAM_CPU_SLOT_0 if slot == 0 else STREAM_CPU_SLOT_1


## Uniform float in [0, 1].
func next_float() -> float:
	return _rng.randf()


## Uniform float in [low, high], blended in GDScript (no C++ FMA path).
func next_range(low: float, high: float) -> float:
	return SimMath.mix(low, high, next_float())


## Uniform integer in [low, high].
func next_int(low: int, high: int) -> int:
	return _rng.randi_range(low, high)
