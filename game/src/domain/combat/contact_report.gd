class_name ContactReport
extends RefCounted

## Earliest contacts found while sweeping one tick (COMBAT §42). `fraction`
## is the tick fraction of the substep where contact began. Blade contact
## outranks body contact in the same substep: the blade got in the way.
##
## See also: /docs/concepts/combat.md

var fraction: float = 1.0
var blade: bool = false
## Closest points on blade 0 (a) and blade 1 (b) at contact.
var blade_ax: float = 0.0
var blade_ay: float = 0.0
var blade_bx: float = 0.0
var blade_by: float = 0.0
## body[i]: fighter i's blade struck the opponent's body at (body_x[i], body_y[i]).
var body: Array[bool] = [false, false]
var body_x: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
var body_y: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
## Two fighter bodies overlapped — a shoulder check or bump.
var body_push: bool = false
## True when this is a persistent contact (CONTACTING with ticks_in_contact > 0)
## rather than a new impact. The resolver uses zero restitution for persistent
## contacts and authored restitution for new impacts.
var body_push_persistent: bool = false
var body_push_nx: float = 0.0
var body_push_ny: float = 0.0
## Sword-body nonpenetration: attacker[i]'s blade is in CONSTRAINING phase
## inside the defender's body. The resolver enforces a zero-restitution
## velocity constraint to prevent the blade from advancing through.
var sword_body_constraining: Array[bool] = [false, false]


func clear() -> void:
	fraction = 1.0
	blade = false
	body[0] = false
	body[1] = false
	body_push = false
	body_push_persistent = false
	sword_body_constraining[0] = false
	sword_body_constraining[1] = false


func any() -> bool:
	return blade or body[0] or body[1] or body_push or sword_body_constraining[0] or sword_body_constraining[1]
