class_name StageDefinition
extends Resource

## One stage. The application resolves it into rules and presentation, and a
## match carries it whole from setup to rematch. The simulation never reads
## this resource.
##
## See also: /docs/concepts/presentation.md

enum Basin { NONE, WATER }

@export var stage_id: StringName = &""
@export var display_name: String = ""
@export var blurb: String = ""
## The arena presentation kit the rules name. Not in the rules hash.
@export var kit_id: StringName = &""
@export var has_crowd: bool = true
## A crowd can stand without a bed. The Arena keeps the bed.
@export var has_crowd_bed: bool = true
@export var closed_edge: bool = false
@export var basin: Basin = Basin.NONE
@export var basin_height: float = 0.0


func rules() -> DuelRules:
	var built := StandardDuelRules.pit() if closed_edge else StandardDuelRules.create()
	built.arena_id = kit_id
	return built


## Empty when this stage can start a match.
func problem() -> String:
	if stage_id == &"" or display_name == "" or kit_id == &"":
		return "the stage has no identity"
	if basin == Basin.WATER and not is_finite(basin_height):
		return "a water stage needs a surface height"
	var built := rules()
	if built == null or not built.is_valid():
		return "the stage rules do not start a duel"
	if closed_edge != built.is_closed_edge():
		return "the stage edge does not match its rules"
	return ""
