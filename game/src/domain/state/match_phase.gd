class_name MatchPhase
extends RefCounted

## Simulation match lifecycle. Application screens (menu, results) are a
## separate concept (AppScreen) and never mix with these phases.
##
## See also: /docs/concepts/simulation.md

enum Id {
	ROUND_INTRO,
	ROUND_ACTIVE,
	ROUND_RESULT,
	MATCH_ENDED,
}

## Outcome slots: fighter 0, fighter 1, or a draw.
const NO_WINNER := -1
const DRAW := 2

const REASON_KILL := &"kill"
const REASON_DOUBLE_KILL := &"double_kill"
const REASON_TIMEOUT := &"timeout"
const REASON_SCORE := &"score"
const REASON_ROUND_LIMIT := &"round_limit"
