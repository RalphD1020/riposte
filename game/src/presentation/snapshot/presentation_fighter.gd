class_name PresentationFighter
extends RefCounted

## Read-only presentation facts for one fighter at one tick. Gameplay plane
## coordinates; world projection happens in ArenaTransform.
##
## See also: /docs/concepts/presentation.md

var slot: int = 0
var x: float = 0.0
var y: float = 0.0
var facing: float = 0.0
## Absolute blade angle and relative sword angle (radians, CCW).
var blade_angle: float = 0.0
var weapon_angle: float = 0.0
## |angular speed| of the blade (rad/s), drives trails and swing feel.
var blade_speed: float = 0.0
var charge: float = 0.0
var phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
var commitment: float = 0.0
var stability: float = 1.0
var health: float = 0.0
var max_health: float = 1.0
var body_radius: float = 0.0
var hilt_radius: float = 0.0
var tip_radius: float = 0.0
var threat_time: float = 0.0


func is_alive() -> bool:
	return health > 0.0
