class_name HumanController
extends FighterController

## Local human: one PlayerCommand per tick from accumulated device input.
##
## See also: /docs/concepts/controls.md

var input: HumanInputState = HumanInputState.new()


func command_for(state: MatchState, _slot: int) -> PlayerCommand:
	return input.consume(state.tick)
