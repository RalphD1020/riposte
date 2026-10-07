class_name FighterCueRequest
extends RefCounted

## A typed instruction for fighter-body presentation (flash, haptic, condition).
##
## See also: /docs/architecture/presentation-feedback.md

var slot: int = 0
var kind: Kind = Kind.HIT_FLASH
var intensity: float = 1.0


enum Kind {
	HIT_FLASH,
	HAPTIC_BLADE,
	HAPTIC_BODY,
	HAPTIC_CRITICAL,
}


static func hit_flash(p_slot: int, p_intensity: float) -> FighterCueRequest:
	var req := FighterCueRequest.new()
	req.slot = p_slot
	req.kind = Kind.HIT_FLASH
	req.intensity = p_intensity
	return req


static func haptic(p_slot: int, p_kind: Kind) -> FighterCueRequest:
	var req := FighterCueRequest.new()
	req.slot = p_slot
	req.kind = p_kind
	return req
