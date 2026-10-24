class_name StageCatalog
extends RefCounted

## The stages Fight Setup may start. The End is listed only when its deck and
## kit load. The open disc is a fixture stage and is never listed.
##
## See also: /docs/concepts/presentation.md

const DECK_SCENE := "res://assets/generated/arenas/end_stage.glb"
const DECK_KIT := "res://assets/presentation/arenas/end/end_stage_kit.tres"


static func playable() -> Array[StageDefinition]:
	var stages: Array[StageDefinition] = [arena()]
	var end := the_end()
	if end.problem() == "" and ResourceLoader.exists(DECK_SCENE) and ResourceLoader.exists(DECK_KIT):
		stages.append(end)
	return stages


## The default stage.
static func arena() -> StageDefinition:
	var stage := StageDefinition.new()
	stage.stage_id = ContentIds.ARENA_STANDARD
	stage.kit_id = ContentIds.ARENA_STANDARD
	stage.display_name = "The Arena"
	stage.blurb = "Sand pit. Closed edge."
	stage.has_crowd = true
	stage.has_crowd_bed = true
	stage.closed_edge = true
	stage.basin = StageDefinition.Basin.NONE
	return stage


static func the_end() -> StageDefinition:
	var stage := StageDefinition.new()
	stage.stage_id = ContentIds.ARENA_END
	stage.kit_id = ContentIds.ARENA_END
	stage.display_name = "The End"
	stage.blurb = "Open deck. No crowd."
	stage.has_crowd = false
	stage.has_crowd_bed = false
	stage.closed_edge = false
	stage.basin = StageDefinition.Basin.NONE
	return stage


## Version 58 on the Arena kit. Ring-out journeys and the CPU ladder play here.
static func open_disc() -> StageDefinition:
	var stage := StageDefinition.new()
	stage.stage_id = ContentIds.STAGE_OPEN_DISC
	stage.kit_id = ContentIds.ARENA_STANDARD
	stage.display_name = "Open Disc"
	stage.blurb = "Version 58. Open edge."
	stage.has_crowd = true
	stage.has_crowd_bed = true
	stage.closed_edge = false
	stage.basin = StageDefinition.Basin.NONE
	return stage


## A listed stage by id, or null.
static func of(stage_id: StringName) -> StageDefinition:
	for stage: StageDefinition in playable():
		if stage.stage_id == stage_id:
			return stage
	return null
