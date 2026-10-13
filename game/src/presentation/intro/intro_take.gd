class_name IntroTake
extends RefCounted

## One fighter's recorded showcase cut for the set intro: presentation
## snapshots one simulation tick apart (PRES-INTRO-001). The director poses an
## intro-only figure from it exactly as the match presenter poses a proxy, so
## the intro is real play, replayed.
##
## See also: /docs/concepts/presentation.md

var frames: Array[PresentationSnapshot] = []


static func of(recorded: Array[PresentationSnapshot]) -> IntroTake:
	var take := IntroTake.new()
	take.frames = recorded
	return take


func is_empty() -> bool:
	return frames.is_empty()


## Seconds the take covers.
func duration() -> float:
	return float(maxi(frames.size() - 1, 0)) * SimulationTimebase.TICK_SECONDS


## The frame at or before `seconds` into the take (held at either end).
func index_at(seconds: float) -> int:
	return clampi(floori(maxf(seconds, 0.0) / SimulationTimebase.TICK_SECONDS), 0, maxi(frames.size() - 1, 0))


## How far past `index_at(seconds)` toward the next frame `seconds` is, in
## [0, 1); 0 once the take has ended.
func blend_at(seconds: float) -> float:
	var index := index_at(seconds)
	if index >= frames.size() - 1:
		return 0.0
	return clampf(maxf(seconds, 0.0) / SimulationTimebase.TICK_SECONDS - float(index), 0.0, 1.0)
