class_name RingOutWater
extends RefCounted

## Where a living ring-out is drawn when a stage requests water. The stage
## gives the surface height; there is no default. `FallPresentationRequest.root_at`
## stays the ballistic root. This follows that root until the shoulders meet
## the basin, then holds a short float so the head and shoulders stay above
## the water. A corpse does not use this. A sword does not use this.
##
## See also: /docs/concepts/presentation.md

## A body reading used to place the float. Not a claim that the shoulders are
## the right water line until the trajectory is watched in Compatibility.
const SHOULDER_HEIGHT := 1.45
const POKE := 0.22
const BOB_AMPLITUDE := 0.035
const BOB_RATE := 2.2
## After entry the root eases onto the float. Position matches `root_at` at
## the entry instant. Horizontal speed decays instead of stopping in one frame.
const SETTLE_SECONDS := 0.45
const DRIFT_TAU := 0.28


static func entry_time(request: FallPresentationRequest, surface: float) -> float:
	var drop := request.exit_position.y - (surface - SHOULDER_HEIGHT)
	if drop <= 0.0:
		return 0.0
	return request.ledge_seconds + sqrt(2.0 * drop / FallPresentationRequest.GRAVITY)


static func entered(request: FallPresentationRequest, elapsed: float, surface: float) -> bool:
	return elapsed >= entry_time(request, surface)


static func shown(request: FallPresentationRequest, elapsed: float, reduced_motion: bool, surface: float) -> Vector3:
	var ballistic := request.root_at(elapsed)
	var entry := entry_time(request, surface)
	if elapsed < entry:
		return ballistic
	var at := request.root_at(entry)
	var age := elapsed - entry
	var drift := DRIFT_TAU * (1.0 - exp(-age / DRIFT_TAU))
	var height := lerpf(at.y, _float_y(age, reduced_motion, surface), _settle(age))
	return Vector3(at.x + request.exit_velocity.x * drift, height, at.z + request.exit_velocity.z * drift)


static func velocity(request: FallPresentationRequest, elapsed: float, reduced_motion: bool, surface: float) -> Vector3:
	var entry := entry_time(request, surface)
	if elapsed < entry:
		return request.velocity_at(elapsed)
	var at := request.root_at(entry)
	var age := elapsed - entry
	var decay := exp(-age / DRIFT_TAU)
	var target := _float_y(age, reduced_motion, surface)
	var bob_v := 0.0 if reduced_motion else cos(age * BOB_RATE) * BOB_RATE * BOB_AMPLITUDE
	var vertical := bob_v * _settle(age) + (target - at.y) * _settle_rate(age)
	return Vector3(request.exit_velocity.x * decay, vertical, request.exit_velocity.z * decay)


static func _float_y(age: float, reduced_motion: bool, surface: float) -> float:
	var height := surface - SHOULDER_HEIGHT + POKE
	if not reduced_motion:
		height += sin(age * BOB_RATE) * BOB_AMPLITUDE
	return height


static func _settle(age: float) -> float:
	var u := clampf(age / SETTLE_SECONDS, 0.0, 1.0)
	return u * u * (3.0 - 2.0 * u)


static func _settle_rate(age: float) -> float:
	if age <= 0.0 or age >= SETTLE_SECONDS:
		return 0.0
	var u := age / SETTLE_SECONDS
	return 6.0 * u * (1.0 - u) / SETTLE_SECONDS
