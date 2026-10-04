class_name ReplayController
extends FighterController

## Feeds one fighter's recorded commands back, in order (PLAN Phase 11.3).
##
## See also: /docs/concepts/simulation.md

var _record: ReplayRecord
var _recorded_slot: int = 0
var _index: int = 0


static func create(record: ReplayRecord, slot: int) -> ReplayController:
	var controller := ReplayController.new()
	controller._record = record
	controller._recorded_slot = slot
	return controller


func command_for(state: MatchState, _slot: int) -> PlayerCommand:
	if _index >= _record.tick_count():
		return PlayerCommand.idle(state.tick)
	var command := _record.command_at(_recorded_slot, _index)
	_index += 1
	return command
