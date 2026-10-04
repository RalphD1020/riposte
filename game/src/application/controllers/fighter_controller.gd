class_name FighterController
extends RefCounted

## The command-source seam (COMBAT §69). Every controller — human, CPU,
## replay, training dummy, and future network peers — answers one question
## per tick: which PlayerCommand does this fighter send? Controllers read
## state; they never mutate it. The base controller idles.
##
## See also: /docs/concepts/simulation.md


func command_for(state: MatchState, _slot: int) -> PlayerCommand:
	return PlayerCommand.idle(state.tick)
