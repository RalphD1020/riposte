class_name StageObjectDef
extends RefCounted

## One structure on the stage, as the combat simulation sees it
## (STRUCTURE-CONTACT-001): a stable id, simplified collision shapes, one
## material, what it blocks, and how it moves. Not a Blender object and not a
## scene node — the render mesh is presentation and never collides. Rules
## content: a structure that moves contacts is a rules change.
##
## Static is the only motion today. A structure never takes an impulse: it is
## the world side of a contact (zero inverse mass, zero velocity).
##
## What a contact with it means is fixed for every structure: it blocks. It
## never damages, never parries, never scores, and never counts as meeting the
## opponent. A swing it actually stops ends through the one arrest law, like
## any contact (RIGID-CONTACT-002).
##
## See also: /docs/concepts/combat.md

enum Motion { STATIC }

var object_id: StringName = &""
var material: ContactMaterial
var shapes: Array[StructureShape] = []
## Which participants it stops. Only blades are implemented; bodies keep their
## support circle (ARENA-001) and are not filtered here.
var blocks_blade: bool = true
var motion: Motion = Motion.STATIC


static func create(id: StringName, surface: ContactMaterial, parts: Array[StructureShape]) -> StageObjectDef:
	var structure := StageObjectDef.new()
	structure.object_id = id
	structure.material = surface
	structure.shapes = parts
	return structure


func problem() -> String:
	if object_id == &"":
		return "a structure has no id"
	if material == null or not material.is_valid():
		return "%s has no valid material" % object_id
	if shapes.is_empty():
		return "%s has no shapes" % object_id
	for shape: StructureShape in shapes:
		if shape == null or not shape.is_valid():
			return "%s has an invalid shape" % object_id
	return ""
