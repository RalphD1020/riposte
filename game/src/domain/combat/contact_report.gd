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
## grip[i]: fighter i's blade entered the opponent's grip region — a hand
## disc or the handle — which is hurt geometry only
## (GRIP-NONBLOCKING-001): damage, no constraint, and the sweep carries on.
## The struck point in the opponent's sword frame is `grip_along[i]` down the
## blade from the pommel and `grip_across[i]` across it (+ toward perp(û));
## `grip_source[i]` which part was entered first (a `DuelEventKeys.SOURCE_*`);
## `grip_fraction[i]` the sweep fraction it was entered at.
var grip: Array[bool] = [false, false]
var grip_along: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
var grip_across: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
var grip_source: Array[String] = ["", ""]
var grip_fraction: PackedFloat64Array = PackedFloat64Array([0.0, 0.0])
## Two fighter bodies overlapped — a shoulder check or bump.
var body_push: bool = false
## True when this is a persistent contact (CONTACTING with ticks_in_contact > 0)
## rather than a new impact. The resolver uses zero restitution for persistent
## contacts and authored restitution for new impacts.
var body_push_persistent: bool = false
var body_push_nx: float = 0.0
var body_push_ny: float = 0.0
## A pair already in contact (the blades past their first clash, a sword
## inside a body's entry lifecycle) came back into touch in this substep. It
## is not a new contact — no impulse, no damage — but the persistent normal
## constraint must hold it here (RIGID-CONTACT-001).
var persistent: bool = false


func clear() -> void:
	fraction = 1.0
	blade = false
	body[0] = false
	body[1] = false
	grip[0] = false
	grip[1] = false
	body_push = false
	body_push_persistent = false
	persistent = false


func any() -> bool:
	return blade or body[0] or body[1] or grip[0] or grip[1] or body_push or persistent
