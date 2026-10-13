class_name DroppedWeapon3D
extends RigidBody3D

## A sword that has left the hands: a presentation-only rigid body carrying a
## fresh copy of the weapon's look, built from its kits. It collides with the
## presentation floor and nothing else, so it lands on the platform or tumbles
## off the edge — and it never touches anything authoritative or reports back
## (PRES-001). Its motion is engine physics on Godot physics time (PRES-TIME-001),
## so it is judged by device QA, not by unit tests; its layers, mass, and launch
## are the testable contract.
##
## The motion is physics-consistent from the captured launch state, for a
## simplified collider: one thin slab over the blade, with the engine's
## automatic centre of mass at that slab's middle. The real sword balances
## nearer the guard; collider, centre of mass, friction, bounce, and angular
## damping are device-QA tuning knobs, not claims of physical accuracy.
##
## See also: /docs/concepts/presentation.md

## Thin collision slab along the blade (m).
const THICKNESS := 0.04
## Below this the sword has fallen out of the arena and is discarded.
const DISCARD_Y := -30.0


## `visual` is the weapon look, laid out along local +Z from the hilt like the
## sword pivot it replaces. `weapon_mass` is the authored weapon's mass (kg):
## the prop tumbles as the sword the simulation modelled. `length` / `width` /
## `center_z` size the collision slab over the blade.
static func create(visual: Node3D, weapon_mass: float, length: float, width: float, center_z: float) -> DroppedWeapon3D:
	var body := DroppedWeapon3D.new()
	body.name = "DroppedWeapon"
	body.mass = weapon_mass
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
	return body


## Place a body that is already in the tree and set it moving. A newly placed
## physics body must not interpolate from wherever it was created, so the
## interpolation history is reset after positioning and before it moves.
func launch(at: Transform3D, linear: Vector3, angular: Vector3) -> void:
	global_transform = at
	reset_physics_interpolation()
	linear_velocity = linear
	angular_velocity = angular


func _physics_process(_delta: float) -> void:
	if global_position.y < DISCARD_Y:
		queue_free()
