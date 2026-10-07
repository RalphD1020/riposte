class_name WeaponBodyContact
extends RefCounted

## Entry-contact lifecycle for one attacker's weapon against one target's body
## (COMBAT-007). Damage happens only on OUTSIDE → ENTERED; the lifecycle
## rearms after a genuine geometric exit with separation hysteresis.
##
## ```text
## OUTSIDE  --blade enters body---------->  ENTERED   (damage here)
## ENTERED  --still overlapping----------->  INSIDE
## INSIDE   --gap > touch + epsilon------->  EXITED
## EXITED   --gap still > touch + eps----->  OUTSIDE   (rearmed)
## EXITED   --gap <= touch--------------->  INSIDE     (re-entered without full sep)
## ```
##
## No invulnerability timer — geometry decides when the weapon has left.
##
## Implements: /spec/invariants.md#combat-007
## See also: /docs/concepts/combat.md

enum Phase {
	OUTSIDE,
	ENTERED,
	INSIDE,
	EXITED,
}

var phase: Phase = Phase.OUTSIDE


func reset() -> void:
	phase = Phase.OUTSIDE


## Advance the lifecycle from an observed gap between the blade and the
## target body. Returns true only when the weapon enters for the first
## time after a full separation — this is the only moment damage is applied.
func observe(gap: float, touch: float, epsilon: float) -> bool:
	match phase:
		Phase.OUTSIDE:
			if gap <= touch:
				phase = Phase.ENTERED
				return true
		Phase.ENTERED:
			phase = Phase.INSIDE
		Phase.INSIDE:
			if gap > touch + epsilon:
				phase = Phase.EXITED
		Phase.EXITED:
			if gap <= touch:
				phase = Phase.INSIDE
			elif gap > touch + epsilon:
				phase = Phase.OUTSIDE
	return false


func is_inside() -> bool:
	return phase == Phase.INSIDE or phase == Phase.ENTERED
