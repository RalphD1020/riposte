class_name IntroRehearsal
extends RefCounted

## The set intro's showcase cuts, recorded by playing them (PRES-INTRO-001).
##
## Each fighter's beat is a short take of real play: from the round's 45°
## start guard the fighter steps in, winds back while walking, and releases a
## cut — the same commands a player would send, stepped through the real
## `DuelSimulation` on a throwaway `MatchState` and projected through
## `SnapshotProjector`. So the intro moves exactly as the game does, on the
## current rules, track and rig, and can never drift back to an older system
## the way a hand-authored flourish did. It never touches the match's own
## state: the match's first authoritative tick is the same with or without it.
##
## See also: /docs/concepts/presentation.md

## The featured fighter's script, in ticks from the round going live: a
## measured step in, a press that becomes a wind-back while still walking,
## and a release from the wound-back start guard.
const STEP_FROM := 4
const STEP_UNTIL := 34
const STEP_AXIS := 0.55
const PRESS_AT := 8
const RELEASE_AT := 34
## Ticks recorded after the round goes live: the step, the cut, and its
## overswing settling into recovery.
const TAKE_TICKS := 70


## One take for `featured`, starting on the tick the round goes live. Empty
## when the rules cannot run (they fail closed elsewhere first).
static func record(rules: DuelRules, seed_value: int, featured: int) -> Array[PresentationSnapshot]:
	var frames: Array[PresentationSnapshot] = []
	var simulation := DuelSimulation.create(rules)
	if simulation == null:
		return frames
	var state := simulation.new_match(seed_value)
	for _tick in rules.intro_ticks + 1:
		if state.phase != MatchPhase.Id.ROUND_INTRO:
			break
		simulation.step(state, PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick))
	frames.append(SnapshotProjector.project(state, rules))
	for tick in TAKE_TICKS:
		var commands: Array[PlayerCommand] = [PlayerCommand.idle(state.tick), PlayerCommand.idle(state.tick)]
		commands[featured] = command_at(tick, state.tick)
		simulation.step(state, commands[0], commands[1])
		frames.append(SnapshotProjector.project(state, rules))
	return frames


## The featured fighter's command `t` ticks into the take.
static func command_at(t: int, tick_value: int) -> PlayerCommand:
	var axis := STEP_AXIS if t >= STEP_FROM and t < STEP_UNTIL else 0.0
	return PlayerCommand.create(tick_value, 0.0, axis, t == PRESS_AT, t == RELEASE_AT)
