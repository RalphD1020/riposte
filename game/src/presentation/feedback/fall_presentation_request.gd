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
## A raw ragdoll started at the ledge could flop backward or snag and visually
## deny the knockback, so the root is always this trajectory; a ragdoll may later
## own only the limbs.
##
## See also: /docs/concepts/presentation.md

## Presentation gravity (m/s²) pulling a falling body down off the platform.
const GRAVITY := 9.8

var slot: int = 0
## Where the fighter crossed the edge, on the arena plane (world, y = 0).
var exit_position: Vector3 = Vector3.ZERO
## Horizontal momentum carried over the edge (world, m/s; y = 0).
var exit_velocity: Vector3 = Vector3.ZERO
## Deterministic per-event key, so a replay falls the same way.
var key: int = 0


static func create(p_slot: int, p_exit_position: Vector3, p_exit_velocity: Vector3, p_key: int) -> FallPresentationRequest:
	var request := FallPresentationRequest.new()
	request.slot = p_slot
	request.exit_position = p_exit_position
	request.exit_velocity = Vector3(p_exit_velocity.x, 0.0, p_exit_velocity.z)
	request.key = p_key
	return request


## The body's root `t` seconds after crossing the edge: the exit momentum
## carried forward unchanged, with gravity drawing it down. Pure.
func root_at(t: float) -> Vector3:
	var elapsed := maxf(t, 0.0)
	return exit_position + exit_velocity * elapsed + Vector3(0.0, -0.5 * GRAVITY * elapsed * elapsed, 0.0)
