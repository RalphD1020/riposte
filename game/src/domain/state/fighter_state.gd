class_name FighterState
extends RefCounted

## Authoritative fighter state (COMBAT §6). Scalar fields only: positions and
## velocities are meters / meters per second on the X/Y gameplay plane;
## facing is radians counter-clockwise from +X.
##
## See also: /docs/concepts/combat.md

var slot: int = 0
## Which end of the arena this fighter belongs to (SIDE-001). Assigned once at
## match setup and constant thereafter. It is stored rather than derived from
## the slot because side is identity: the camera, the spawn, and the
## presentation all read it, and inferring it from slot would quietly make
## slot 0 mean "south" everywhere.
var side: DuelSide.Id = DuelSide.Id.LIGHT_SOUTH
var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
## Body acceleration over the previous tick, m/s². Persisted because a
## collision has to know how violently the body was changing its own motion at
## the instant of impact: control authority spent fighting your own momentum is
## not supporting the strike (COMBAT §62).
var ax: float = 0.0
var ay: float = 0.0
var facing: float = 0.0
## Last bearing toward the opponent that was numerically meaningful, as a unit
## vector. Footwork is expressed relative to this axis, and it is remembered so
## that two fighters standing on the same spot keep moving the way they were
## rather than snapping to an invented direction (COMBAT §25.1).
var duel_forward_x: float = 1.0
var duel_forward_y: float = 0.0
## Body angular velocity, rad/s. Driven by bounded torque against the body's
## moment of inertia, never clamped down directly (PHYS-003).
var turn_rate: float = 0.0
var health: float = 0.0
## Exertion resource (STAMINA-001). Drains from motor effort, recovers at
## rest, and takes a shock on damage. The ceiling is derived from health via
## `StaminaModel.max_for_health()` — never stored — so injury is the cause
## and reduced ceiling is the consequence.
var stamina: float = 0.0
## Balance B ∈ [floor, 1] (COMBAT §36).
var stability: float = 1.0
var stagger_left: int = 0
## Tick fraction of the blow that killed this fighter, or `ALIVE` while they
## still stand. Recorded because a trade is decided by who fell *first*, and
## within one tick that is a sub-tick question (COMBAT §58).
var lethal_fraction: float = ALIVE
var weapon: WeaponState = WeaponState.new()
## Where this fighter is inside a double-tap footwork gesture (MOVE-002).
var gesture: MovementGestureState = MovementGestureState.new()
## True once the fighter's center crosses the arena edge. Authoritative,
## hashed, and reset per round. Falling fighters are removed from collision
## and invariant-exempt for position bounds.
var is_falling: bool = false

## Sentinel for "has not been killed". Negative so any real time of impact,
## including exactly 0.0, compares as earlier.
const ALIVE := -1.0

## Attack input, reconstructed from command edges by the simulation.
var attack_held: bool = false
var press_tick: int = -1
var buffered_press_tick: int = -1
var buffered_release: bool = false


func is_alive() -> bool:
	return health > 0.0


func speed() -> float:
	return SimMath.length(vx, vy)


func acceleration() -> float:
	return SimMath.length(ax, ay)


func clear_attack_input() -> void:
	attack_held = false
	press_tick = -1
	buffered_press_tick = -1
	buffered_release = false
