class_name WeaponBodyContact
extends RefCounted

## Entry-contact lifecycle for one attacker's weapon against one target's body
## (COMBAT-007, PHYS-010). Damage happens only on OUTSIDE → ENTERED; the
## lifecycle then diverges: nonlethal contacts enforce nonpenetration in
## CONSTRAINING, while lethal contacts release the constraint in PENETRATING.
## The lifecycle rearms after a genuine geometric exit with separation
## hysteresis.
##
## ```text
## OUTSIDE  --blade enters body---------->  ENTERED   (damage + bilateral impulse)
## ENTERED  --nonlethal------------------>  CONSTRAINING  (nonpenetration)
## ENTERED  --lethal point--------------->  PENETRATING   (constraint released)
## CONSTRAINING --gap > touch + epsilon-->  EXITING
## PENETRATING  --gap > touch + epsilon-->  EXITING
## EXITING  --gap still > touch + eps---->  OUTSIDE   (rearmed)
## EXITING  --gap <= touch--------------->  CONSTRAINING  (re-entered)
## ```
##
## No invulnerability timer — geometry decides when the weapon has left.
##
## Implements: /spec/invariants.md#combat-007
## Implements: /spec/invariants.md#phys-010
## See also: /docs/concepts/combat.md

enum Phase {
	OUTSIDE,
	ENTERED,
	CONSTRAINING,
	PENETRATING,
	EXITING,
}

var phase: Phase = Phase.OUTSIDE


func reset() -> void:
	phase = Phase.OUTSIDE


## Advance the lifecycle after the entry impulse has been resolved.
## Called by the contact resolver after evaluating the strike. Nonlethal
## contacts enter CONSTRAINING (blade cannot pass through body); lethal
## contacts enter PENETRATING (blade continues through).
func advance_after_entry(lethal: bool) -> void:
	if phase != Phase.ENTERED:
		return
	phase = Phase.PENETRATING if lethal else Phase.CONSTRAINING


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
			## Entry was not advanced by the resolver — treat as constraining.
			phase = Phase.CONSTRAINING
		Phase.CONSTRAINING:
			if gap > touch + epsilon:
				phase = Phase.EXITING
		Phase.PENETRATING:
			if gap > touch + epsilon:
				phase = Phase.EXITING
		Phase.EXITING:
			if gap <= touch:
				phase = Phase.CONSTRAINING
			elif gap > touch + epsilon:
				phase = Phase.OUTSIDE
	return false


func is_inside() -> bool:
	return phase == Phase.CONSTRAINING or phase == Phase.PENETRATING or phase == Phase.ENTERED
