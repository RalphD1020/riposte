class_name DeathPresentationRequest
extends RefCounted

## A killing blow, as presentation needs it: who died, from what kind of blow,
## which way it struck, and how hard. Derived only from the authoritative
## outcome — the death is already decided when this exists — and no backend
## may write any of it back (PRES-001). The same request drives whichever
## backend carries out the death (the primitive collapse now, a ragdoll later),
## so swapping the backend can never reach the simulation.
##
## See also: /docs/concepts/presentation.md

var slot: int = 0
## Who struck the killing blow, or -1 if no fighter did. A killing thrust holds
## this fighter in the follow-through; a non-lethal thrust never reaches here.
var killer: int = -1
var cause: DeathPresentationProfile.Family = DeathPresentationProfile.Family.SLASH
## Unit direction the killing blow travelled, on the arena plane (world).
var impact_direction: Vector3 = Vector3.ZERO
## How hard it landed, as the strike's response (0 = barely, 1+ = devastating).
var impact_severity: float = 0.0
## Deterministic per-event key, so a replay dies the same way.
var key: int = 0


static func create(p_slot: int, p_cause: DeathPresentationProfile.Family, p_direction: Vector3, p_severity: float, p_key: int, p_killer: int = -1) -> DeathPresentationRequest:
	var request := DeathPresentationRequest.new()
	request.slot = p_slot
	request.killer = p_killer
	request.cause = p_cause
	request.impact_direction = p_direction
	request.impact_severity = maxf(p_severity, 0.0)
	request.key = p_key
	return request
