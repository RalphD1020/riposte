class_name WeaponCueRequest
extends RefCounted

## A typed instruction for weapon presentation (tension, release).
##
## See also: /docs/architecture/presentation-feedback.md

var slot: int = 0
var kind: Kind = Kind.TENSION_HOLD


enum Kind {
	TENSION_HOLD,
	TENSION_RELEASE,
}

## Only meaningful for TENSION_HOLD.
var charge: float = 0.0
var world_position: Vector3 = Vector3.ZERO


static func tension_hold(p_slot: int, p_charge: float, p_world: Vector3) -> WeaponCueRequest:
	var req := WeaponCueRequest.new()
	req.slot = p_slot
	req.kind = Kind.TENSION_HOLD
	req.charge = p_charge
	req.world_position = p_world
	return req


static func tension_release(p_slot: int) -> WeaponCueRequest:
	var req := WeaponCueRequest.new()
	req.slot = p_slot
	req.kind = Kind.TENSION_RELEASE
	return req
