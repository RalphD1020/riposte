class_name DroppedWeapon3D
extends RigidBody3D

## A sword that has left the hands: a presentation-only rigid body carrying a
## copy of the weapon's look. It collides with the presentation floor and
## nothing else, so it lands on the platform or tumbles off the edge — and it
## never touches anything authoritative or reports back (PRES-001). Its motion
## is engine physics on wall-clock time, so it is judged by device QA, not by
## unit tests; its layers and launch are the testable contract.
##
## See also: /docs/concepts/presentation.md

## Presentation mass of a longsword (kg); only shapes the tumble.
const MASS := 1.5
## Thin collision slab along the blade (m).
const THICKNESS := 0.04
## Below this the sword has fallen out of the arena and is discarded.
const DISCARD_Y := -30.0


## `visual` is the copied weapon look, laid out along local +Z from the hilt
## like the sword pivot it came from. `length` / `width` / `center_z` size the
## collision slab over the blade.
static func create(visual: Node3D, linear: Vector3, angular: Vector3, length: float, width: float, center_z: float) -> DroppedWeapon3D:
	var body := DroppedWeapon3D.new()
	body.name = "DroppedWeapon"
	body.mass = MASS
	body.collision_layer = PresentationPhysicsLayers.DROPPED_WEAPON
	body.collision_mask = PresentationPhysicsLayers.PRESENTATION_GROUND
	var shape := BoxShape3D.new()
	shape.size = Vector3(maxf(width, THICKNESS), THICKNESS, maxf(length, THICKNESS))
	var collider := CollisionShape3D.new()
	collider.name = "Blade"
	collider.shape = shape
	collider.position = Vector3(0.0, 0.0, center_z)
	body.add_child(collider)
	body.add_child(visual)
	body.linear_velocity = linear
	body.angular_velocity = angular
	return body


func _physics_process(_delta: float) -> void:
	if global_position.y < DISCARD_Y:
		queue_free()
