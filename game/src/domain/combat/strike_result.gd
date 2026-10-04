class_name StrikeResult
extends RefCounted

## Everything that physically happened at one body contact (COMBAT §51–§55),
## evaluated before any effect is applied so double hits stay symmetric.
##
## See also: /docs/concepts/combat.md

var attacker: int = -1
var target: int = -1
var point_x: float = 0.0
var point_y: float = 0.0
## Unit normal from the contact point into the target's center.
var normal_x: float = 1.0
var normal_y: float = 0.0
var blade_fraction: float = 0.0
var closing_speed: float = 0.0
var alignment: float = 0.0
var efficiency: float = 0.0
var physical_quality: float = 0.0
var exposure: float = 0.0
var quality: float = 0.0
var damage: float = 0.0
var critical: bool = false


func to_payload() -> Dictionary:
	return {
		DuelEventKeys.X: point_x,
		DuelEventKeys.Y: point_y,
		DuelEventKeys.DAMAGE: damage,
		DuelEventKeys.QUALITY: quality,
		DuelEventKeys.PHYSICAL_QUALITY: physical_quality,
		DuelEventKeys.EXPOSURE: exposure,
		DuelEventKeys.CLOSING_SPEED: closing_speed,
		DuelEventKeys.BLADE_FRACTION: blade_fraction,
		DuelEventKeys.ALIGNMENT: alignment,
		DuelEventKeys.CRITICAL: critical,
	}
