class_name ScenarioController
extends FighterController

## Test-only scripted opponent for FULL-E2E. A scenario installs it through
## `RiposteApp.compose_session`, opposite the real human input pipeline, so a
## specific terminal outcome (a shove off the edge, a standing target) can be
## driven through the real app, clock, solver, and presenter. It reads state
## and returns a command, like every controller; it never mutates anything.
##
## See also: /docs/reference/testing.md

var script_fn: Callable


static func of(fn: Callable) -> ScenarioController:
	var controller := ScenarioController.new()
	controller.script_fn = fn
	return controller


static func standing() -> ScenarioController:
	return of(func(state: MatchState, _slot: int) -> PlayerCommand: return PlayerCommand.idle(state.tick))


func command_for(state: MatchState, slot: int) -> PlayerCommand:
	return script_fn.call(state, slot) as PlayerCommand
