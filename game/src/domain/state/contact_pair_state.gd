class_name ContactPairState
extends RefCounted

## The lifecycle of one pair of colliding parts (COMBAT §43–§45).
##
## Two blades that touch are not a sequence of independent strikes. A single
## clash lasts several ticks, and whether the next tick is "still that clash"
## or "a fresh one" is a real question with a real answer: the parts must
## genuinely come apart first.
##
## ```text
## SEPARATED  --gap <= touch-------------->  CONTACTING   (a new contact)
## CONTACTING --closing < bind_speed------>  BOUND
## CONTACTING --gap > touch--------------->  SEPARATING
## BOUND      --bind resolved------------->  SEPARATING
## SEPARATING --gap > touch + epsilon----->  SEPARATED
## SEPARATING --gap <= touch-------------->  CONTACTING   (not a new contact)
## ```
##
## The epsilon is what makes this stable: a blade resting exactly on the touch
## distance would otherwise re-strike every tick. It replaces the arbitrary
## cooldown counter this used to be — separation is physical, a timer is not.
##
## Modelled as a *pair* even though MVP-0 tracks only blade-on-blade, so
## sword-and-shield, staff ends, and dual wield add instances rather than
## force a rewrite.
##
## Implements: /spec/invariants.md#combat-002
## See also: /docs/concepts/combat.md

enum Phase {
	SEPARATED,
	CONTACTING,
	BOUND,
	SEPARATING,
}

var phase: Phase = Phase.SEPARATED
## Ticks spent in the current phase. The bind fail-safe reads this, so a bind
## can never outlive its bound however it was entered.
var phase_ticks: int = 0


func reset() -> void:
	phase = Phase.SEPARATED
	phase_ticks = 0


func set_phase(next: Phase) -> void:
	if next == phase:
		return
	phase = next
	phase_ticks = 0


func tick() -> void:
	phase_ticks += 1


func is_bound() -> bool:
	return phase == Phase.BOUND


## Advance the lifecycle from an observed gap. Returns true when this
## observation *begins* a new contact, which is the only moment an impulse is
## resolved.
##
## Only a fully separated pair can begin one: re-touching while still coming
## apart continues the contact it is already in. That rule lives here and
## nowhere else — a second predicate stating it is a second place for it to be
## wrong.
func observe(gap: float, touch: float, separation_epsilon: float) -> bool:
	match phase:
		Phase.SEPARATED:
			if gap <= touch:
				set_phase(Phase.CONTACTING)
				return true
		Phase.CONTACTING:
			if gap > touch:
				set_phase(Phase.SEPARATING)
		Phase.BOUND:
			pass
		Phase.SEPARATING:
			if gap <= touch:
				set_phase(Phase.CONTACTING)
			elif gap > touch + separation_epsilon:
				set_phase(Phase.SEPARATED)
	return false
