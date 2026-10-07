class_name MatchPhase
extends RefCounted

## Simulation match lifecycle. Application screens (menu, results) are a
## separate concept (AppScreen) and never mix with these phases.
##
## See also: /docs/concepts/simulation.md

enum Id {
	ROUND_INTRO,
	ROUND_ACTIVE,
	POST_ROUND_FREE,
	ROUND_RESULT,
	MATCH_ENDED,
}

## Outcome slots: fighter 0, fighter 1, or a draw.
const NO_WINNER := -1
const DRAW := 2

const REASON_KILL := &"kill"
## A qualifying emergent point strike was lethal (COMBAT-010/011).
const REASON_LETHAL_THRUST := &"lethal_thrust"
## Both fighters died this tick, but one blade arrived first. The round goes
## to whoever was still standing at that instant (COMBAT §58).
const REASON_TRADE_FIRST_CONTACT := &"trade_first_contact"
## Both died at the same instant. Nothing separates them, so nobody wins.
const REASON_DOUBLE_KILL := &"double_kill"
const REASON_TIMEOUT := &"timeout"
const REASON_SCORE := &"score"
const REASON_ROUND_LIMIT := &"round_limit"
## Authoritative state failed an invariant; the match is void, not a result.
const REASON_NO_CONTEST := &"no_contest"
const REASON_RING_OUT := &"ring_out"
