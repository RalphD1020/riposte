class_name ArenaTransform
extends RefCounted

## The only conversion from the gameplay plane to the 3D world. Gameplay +X
## is world +X (screen right) and gameplay +Y is world -Z (screen up, away
## from the camera). Models face local +Z (Godot MODEL_FRONT), so a gameplay
## heading θ is a world yaw of θ + π/2. World values never feed back into the
## simulation.
##
## See also: /docs/concepts/presentation.md


static func to_world(x: float, y: float, height: float = 0.0) -> Vector3:
	return Vector3(x, height, -y)


static func to_plane(world: Vector3) -> Vector2:
	return Vector2(world.x, -world.z)


static func yaw(heading: float) -> float:
	return heading + PI * 0.5


static func direction(heading: float) -> Vector3:
	return Vector3(cos(heading), 0.0, -sin(heading))
