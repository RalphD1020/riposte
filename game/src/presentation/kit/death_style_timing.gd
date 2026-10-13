class_name DeathStyleTiming
extends Resource

## When one death style's choreography hands things over, in presentation-scaled
## seconds from the killing blow (PRES-TIME-001): when the dead hand lets the
## sword go, and when a future ragdoll backend may take the limbs. Owned by the
## kit beside the clip it times, so a slow fold-over-the-blade and a fast
## backward drop never share one global release beat.
##
## See also: /docs/concepts/presentation.md

@export var weapon_release_time: float = DeathPresentationProfile.DEFAULT_WEAPON_RELEASE
## Negative: this style never hands over to a ragdoll.
@export var ragdoll_handoff_time: float = -1.0


static func of(release: float, handoff: float = -1.0) -> DeathStyleTiming:
	var timing := DeathStyleTiming.new()
	timing.weapon_release_time = maxf(release, 0.0)
	timing.ragdoll_handoff_time = handoff
	return timing
