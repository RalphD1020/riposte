class_name CombatPhase
extends RefCounted

## Explicit weapon phases (COMBAT §22). Never a single ATTACKING boolean.
##
## See also: /docs/concepts/combat.md

enum Id {
	NEUTRAL,
	CHARGING,
	LAUNCH,
	ACTIVE_EARLY,
	ACTIVE_THREAT,
	ACTIVE_LATE,
	OVERSWING,
	RECOVERY,
	BIND,
	STAGGER,
	DEAD,
}


## Motor still driving the swing toward its end angle.
static func is_swinging(phase: Id) -> bool:
	return phase == Id.LAUNCH or phase == Id.ACTIVE_EARLY or phase == Id.ACTIVE_THREAT or phase == Id.ACTIVE_LATE


## Blade carries a strike and may deal body damage.
static func is_striking(phase: Id) -> bool:
	return is_swinging(phase) or phase == Id.OVERSWING


static func label(phase: Id) -> String:
	match phase:
		Id.NEUTRAL:
			return "NEUTRAL"
		Id.CHARGING:
			return "CHARGING"
		Id.LAUNCH:
			return "LAUNCH"
		Id.ACTIVE_EARLY:
			return "ACTIVE_EARLY"
		Id.ACTIVE_THREAT:
			return "ACTIVE_THREAT"
		Id.ACTIVE_LATE:
			return "ACTIVE_LATE"
		Id.OVERSWING:
			return "OVERSWING"
		Id.RECOVERY:
			return "RECOVERY"
		Id.BIND:
			return "BIND"
		Id.STAGGER:
			return "STAGGER"
		Id.DEAD:
			return "DEAD"
	return "UNKNOWN"
