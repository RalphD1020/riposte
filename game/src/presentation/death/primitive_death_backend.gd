class_name PrimitiveDeathBackend
extends DeathPresentationBackend

## The always-available death: the proxy's own procedural collapse, chosen from
## the fighter kit's `DeathPresentationProfile`. It runs on every device and
## needs no physical skeleton, so it is the production fallback the controller
## always ends on — a fighter dies with character before any ragdoll exists.
##
## See also: /docs/concepts/presentation.md

var _fighters: Array[FighterPresentation3D] = []


func _init(fighters: Array[FighterPresentation3D]) -> void:
	_fighters = fighters


## The victim collapses; on a killing thrust the striker also holds the
## run-through. Reached only from a death request, so a thrust that does not
## kill can never lock the striker (the lock is the kill, not the stab).
func start(request: DeathPresentationRequest) -> void:
	_fighters[request.slot].begin_death(request.cause, request.key)
	if request.cause == DeathPresentationProfile.Family.STAB and request.killer >= 0 and request.killer != request.slot:
		_fighters[request.killer].begin_finisher()
