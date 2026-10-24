class_name FallPresentationRequest
extends RefCounted

## A ring-out, as presentation needs it: who lost their footing, exactly where
## they crossed the edge, and the momentum they carried over it. The simulation
## ends the round the tick a fighter falls, so authority stops moving them at
## the ledge; presentation then owns the root trajectory, carrying the body
## outward along the real exit velocity while presentation gravity takes it
## down. The fall therefore reads the knockback that caused it — a fighter
## shoved hard flies out, one who stepped off drops close to the edge — and
## never contradicts it (PRES-001). Nothing here is written back.
##
## A drawn floor can reach past the support circle (The End's octagon corners
## and lip). The root then slides on that drawn top until it clears the
## outline, so the body never sinks through visible ground (`leave_ground`).
##
## A raw ragdoll started at the ledge could flop backward or snag and visually
## deny the knockback, so the root is always this trajectory; a ragdoll may later
## own only the limbs.
##
## See also: /docs/concepts/presentation.md

## Presentation gravity (m/s²) pulling a falling body down off the platform.
const GRAVITY := 9.8
## Longest slide on a drawn overhang (s). A body barely moving at the edge
## still drops instead of standing on decoration.
const LEDGE_LIMIT := 0.6

var slot: int = 0
## Where the fighter crossed the edge, on the arena plane (world, y = 0).
var exit_position: Vector3 = Vector3.ZERO
## Horizontal momentum carried over the edge (world, m/s; y = 0).
var exit_velocity: Vector3 = Vector3.ZERO
## Deterministic per-event key, so a replay falls the same way.
var key: int = 0
## Seconds the root stays on the drawn floor before gravity takes it.
var ledge_seconds: float = 0.0


static func create(p_slot: int, p_exit_position: Vector3, p_exit_velocity: Vector3, p_key: int) -> FallPresentationRequest:
	var request := FallPresentationRequest.new()
	request.slot = p_slot
	request.exit_position = p_exit_position
	request.exit_velocity = Vector3(p_exit_velocity.x, 0.0, p_exit_velocity.z)
	request.key = p_key
	return request


## The body's root `t` seconds after crossing the edge: the exit momentum
## carried forward unchanged, with gravity drawing it down once it is off the
## drawn floor. Pure.
func root_at(t: float) -> Vector3:
	var elapsed := maxf(t, 0.0)
	var drop := maxf(elapsed - ledge_seconds, 0.0)
	return exit_position + exit_velocity * elapsed + Vector3(0.0, -0.5 * GRAVITY * drop * drop, 0.0)


func velocity_at(t: float) -> Vector3:
	var drop := maxf(maxf(t, 0.0) - ledge_seconds, 0.0)
	return exit_velocity + Vector3(0.0, -GRAVITY * drop, 0.0)


## Slide on the drawn floor until the exit path clears `outline`, a convex
## polygon on the world XZ plane (either winding). An empty outline, or a
## crossing already outside it, leaves the fall immediate.
func leave_ground(outline: PackedVector2Array) -> void:
	ledge_seconds = clampf(time_to_leave(outline, Vector2(exit_position.x, exit_position.z), Vector2(exit_velocity.x, exit_velocity.z)), 0.0, LEDGE_LIMIT)


static func time_to_leave(outline: PackedVector2Array, from: Vector2, velocity: Vector2) -> float:
	var count := outline.size()
	if count < 3:
		return 0.0
	var centre := Vector2.ZERO
	for point: Vector2 in outline:
		centre += point
	centre /= float(count)
	var leave := INF
	for i in count:
		var a := outline[i]
		var b := outline[(i + 1) % count]
		var normal := Vector2(b.y - a.y, a.x - b.x).normalized()
		if normal.dot(a - centre) < 0.0:
			normal = -normal
		var slack := normal.dot(a - from)
		if slack <= 0.0:
			return 0.0
		var closing := normal.dot(velocity)
		if closing > 1.0e-9:
			leave = minf(leave, slack / closing)
	return leave if is_finite(leave) else LEDGE_LIMIT
