class_name SetWinningHorn
extends RefCounted

## The fanfare plays once, on the lethal blow that wins the set. A round win,
## a ring-out, and a second observer do not play it again. Rematch clears it
## by constructing a new screen.
##
## See also: /docs/concepts/presentation.md

var fired: bool = false


func consider(set_winner: int, loser_terminal: FighterState.Terminal) -> bool:
	if fired:
		return false
	if not MatchPhase.is_combatant(set_winner):
		return false
	if loser_terminal != FighterState.Terminal.KILLED:
		return false
	fired = true
	return true
