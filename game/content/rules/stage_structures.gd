class_name StageStructures
extends RefCounted

## The collidable structures of each stage, as the combat simulation sees them
## (STRUCTURE-CONTACT-001). Simplified on purpose: the Arena's render bowl is
## tens of thousands of stone blocks; its collision is three objects and nine
## shapes. Authored here from the rules' own dimensions, never read from a
## mesh. `PRES-ARENA` checks that the imported bowl agrees.
##
## The End has none: an open deck has nothing to strike.
##
## See also: /docs/concepts/combat.md

const INNER_WALL := &"arena.inner_wall"
const GATE_NORTH := &"arena.gate.north"
const GATE_SOUTH := &"arena.gate.south"
## The gate opening and its door's recess, on the arena's north-south axis
## (`arena_section.json` `gates`): 2.2 m wide, the door 8.5 m out.
const GATE_HALF_WIDTH := 1.1
const DOOR_RADIUS := 8.5


## The Arena: a stone wall whose face is the support circle, broken north and
## south by two recessed wooden doors. Jambs are straight stone faces, parallel
## to the gate axis, from the wall face back to the door.
static func arena(wall_radius: float) -> Array[StageObjectDef]:
	var half := GATE_HALF_WIDTH
	var face := sqrt(wall_radius * wall_radius - half * half)
	var door := sqrt(DOOR_RADIUS * DOOR_RADIUS - half * half)
	## Unit directions of the jambs on the wall face: ±x over the face height.
	var jx := half / wall_radius
	var jy := face / wall_radius
	var stone: Array[StructureShape] = [
		## West, from the north gate's left jamb counter-clockwise to the south's.
		StructureShape.arc(0.0, 0.0, wall_radius, -jx, jy, -jx, -jy),
		## East, from the south gate's right jamb to the north's.
		StructureShape.arc(0.0, 0.0, wall_radius, jx, -jy, jx, jy),
		StructureShape.segment(half, face, half, door, 0.0),
		StructureShape.segment(-half, face, -half, door, 0.0),
		StructureShape.segment(-half, -face, -half, -door, 0.0),
		StructureShape.segment(half, -face, half, -door, 0.0),
	]
	var north: Array[StructureShape] = [StructureShape.arc(0.0, 0.0, DOOR_RADIUS, half / DOOR_RADIUS, door / DOOR_RADIUS, -half / DOOR_RADIUS, door / DOOR_RADIUS)]
	var south: Array[StructureShape] = [StructureShape.arc(0.0, 0.0, DOOR_RADIUS, -half / DOOR_RADIUS, -door / DOOR_RADIUS, half / DOOR_RADIUS, -door / DOOR_RADIUS)]
	return [
		StageObjectDef.create(INNER_WALL, MaterialCatalog.stone(), stone),
		StageObjectDef.create(GATE_NORTH, MaterialCatalog.wood(), north),
		StageObjectDef.create(GATE_SOUTH, MaterialCatalog.wood(), south),
	]
