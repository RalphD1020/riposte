class_name ContactReport
extends RefCounted

## Earliest contacts found while sweeping one tick (COMBAT §42). `fraction`
## is the tick fraction of the substep where contact began. Inside one
## substep, blade contact outranks a structure, and a structure outranks a
## body: what got in the way first is what the blade met.
##
## See also: /docs/concepts/combat.md

var fraction: float = 1.0
var blade: bool = false
## Closest points on blade 0 (a) and blade 1 (b) at contact.
var blade_ax: float = 0.0
var blade_ay: float = 0.0
var blade_bx: float = 0.0
var blade_by: float = 0.0
## structure[i]: fighter i's sword began a contact with a stage structure
## (STRUCTURE-CONTACT-001). Its points are on `MatchState.structure_contacts[i]`.
var structure: Array[bool] = [false, false]
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
## A pair already in contact (the blades past their first clash, a sword
## inside a body's entry lifecycle, a sword held on a structure) came back
## into touch in this substep. It is not a new contact — no impulse, no
## damage — but the persistent normal constraint must hold it here
## (RIGID-CONTACT-001).
var persistent: bool = false


func clear() -> void:
	fraction = 1.0
	blade = false
	structure[0] = false
	structure[1] = false
	body[0] = false
	body[1] = false
	body_push = false
	body_push_persistent = false
	persistent = false


## A new contact that the resolver turns into an impulse.
func any_new() -> bool:
	return blade or structure[0] or structure[1] or body[0] or body[1] or body_push


func any() -> bool:
	return any_new() or persistent
