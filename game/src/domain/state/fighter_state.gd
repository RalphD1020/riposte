class_name FighterState
extends RefCounted

## Authoritative fighter state (COMBAT §6). Scalar fields only: positions and
## velocities are meters / meters per second on the X/Y gameplay plane;
## facing is radians counter-clockwise from +X.
##
## See also: /docs/concepts/combat.md

var slot: int = 0
var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var facing: float = 0.0
var turn_rate: float = 0.0
var health: float = 0.0
## Balance B ∈ [floor, 1] (COMBAT §36).
var stability: float = 1.0
var stagger_left: int = 0
var weapon: WeaponState = WeaponState.new()

## Attack input, reconstructed from command edges by the simulation.
var attack_held: bool = false
var press_tick: int = -1
var buffered_press_tick: int = -1
var buffered_release: bool = false


func is_alive() -> bool:
	return health > 0.0


func speed() -> float:
	return SimMath.length(vx, vy)


func clear_attack_input() -> void:
	attack_held = false
	press_tick = -1
	buffered_press_tick = -1
	buffered_release = false
