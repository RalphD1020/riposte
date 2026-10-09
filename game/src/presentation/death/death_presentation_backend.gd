class_name DeathPresentationBackend
extends RefCounted

## One way to carry out a death that the simulation has already decided. The
## controller tries backends in order and uses the first that can run this
## request; a backend that cannot (a ragdoll on a rig with no physical skeleton,
## or on a device where it is switched off) says so, and the controller falls
## through until it reaches the primitive collapse, which always runs.
##
## A backend only shapes how the death looks. It never reports back, so no
## choice of backend can change a hit, the winner, or the replay hash.
##
## See also: /docs/concepts/presentation.md


## Whether this backend can carry out `request` here and now.
func is_available(_request: DeathPresentationRequest) -> bool:
	return true


## Carry out the death. Called at most once per fighter per round.
func start(_request: DeathPresentationRequest) -> void:
	pass
