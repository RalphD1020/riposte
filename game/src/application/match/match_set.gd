class_name MatchSet
extends RefCounted

## One set: a single match, first to `rounds_to_win` rounds (PRES-INTRO-001).
## Quick Play and every Rematch open a new set with a fresh `set_id`; rounds
## inside a match never do. The set owns the two once-only presentation beats —
## the fighter introduction at its start and the winner's showcase at its end —
## as claims, so "has this set been introduced?" is a fact about the set rather
## than a boolean that happens to be cleared at the right time.
##
## Player settings and cosmetic choices are not set-scoped; they live on the
## app and outlive every set.
##
## See also: /docs/concepts/ux.md

var set_id: int = 0
var _intro_open: bool = false
var _victory_open: bool = false


static func open(id: int, introduced: bool, celebrated: bool) -> MatchSet:
	var match_set := MatchSet.new()
	match_set.set_id = id
	match_set._intro_open = introduced
	match_set._victory_open = celebrated
	return match_set


## True exactly once, and only for a set that is introduced at all.
func claim_intro() -> bool:
	var due := _intro_open
	_intro_open = false
	return due


## True exactly once, and only for a set whose winner is showcased at all.
func claim_victory() -> bool:
	var due := _victory_open
	_victory_open = false
	return due
