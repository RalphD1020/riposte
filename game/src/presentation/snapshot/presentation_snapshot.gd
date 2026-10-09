class_name PresentationSnapshot
extends RefCounted

## One simulation tick as presentation sees it: match flow, both fighters,
## and relational diagnostics. Presenters read snapshots and events only;
## they never inspect mutable simulation state.
##
## See also: /docs/concepts/presentation.md

var tick: int = 0
var phase: MatchPhase.Id = MatchPhase.Id.ROUND_INTRO
var phase_ticks: int = 0
var round_number: int = 1
var rounds_to_win: int = 3
var scores: PackedInt32Array = PackedInt32Array([0, 0])
var round_winner: int = MatchPhase.NO_WINNER
var match_winner: int = MatchPhase.NO_WINNER
var end_reason: StringName = &""
var intro_ticks: int = 0
var time_left_ticks: int = 0
## How far out from the centre each side's home end sits, so the arena can
## mark its north-south axis where the fighters actually start (SIDE-001).
var spawn_offset: float = 0.0
## The rules' reference impulse (N·s), so presentation can read a body-push
## impulse as a fraction of the reference strike instead of inventing a scale.
var reference_impulse: float = 0.0
var fighters: Array[PresentationFighter] = []
## Debug overlay (COMBAT §76).
var distance: float = 0.0
var closing_speed: float = 0.0
var orbit_rate: float = 0.0


func fighter(slot: int) -> PresentationFighter:
	return fighters[slot]
