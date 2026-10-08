class_name BodyContactState
extends RefCounted

## Body-body contact lifecycle (PHYS-005, PHYS-009). Two fighter bodies are
## either SEPARATED or CONTACTING. The first tick of contact (`ticks_in_contact
## == 0`) is a new impact — restitution applies. Subsequent ticks in contact
## (`ticks_in_contact > 0`) are persistent — only a zero-restitution
## nonpenetration constraint prevents interpenetration.
##
## The contact normal is derived from live geometry each tick and is NOT
## persisted. `prev_normal_x/y` is a fallback for numerically coincident
## centers only.
##
## Implements: /spec/invariants.md#phys-009
## See also: /docs/concepts/combat.md

enum Phase { SEPARATED, CONTACTING }

var phase: Phase = Phase.SEPARATED
## How many ticks this pair has been in continuous contact. Zero on the first
## tick of a new contact (the impact tick). Only incremented at the end of the
## tick when the pair is still CONTACTING.
var ticks_in_contact: int = 0
## Fallback normal for when body centers are numerically coincident. Not
## hashed — derived from live geometry is authoritative.
var prev_normal_x: float = 0.0
var prev_normal_y: float = 0.0
## Last solved constraint impulse and direction, written by the contact
## resolver (PHYS-009, CPU-007). The CPU reads this to derive push pressure
## from observable physics, not from hidden opponent motor intent.
var last_constraint_impulse: float = 0.0
var last_constraint_normal_x: float = 0.0
var last_constraint_normal_y: float = 0.0


func reset() -> void:
	phase = Phase.SEPARATED
	ticks_in_contact = 0
	prev_normal_x = 0.0
	prev_normal_y = 0.0
	last_constraint_impulse = 0.0
	last_constraint_normal_x = 0.0
	last_constraint_normal_y = 0.0


## Call at end of contact lifecycle upkeep each tick. Increments the contact
## counter when the pair is still in contact.
func tick() -> void:
	if phase == Phase.CONTACTING:
		ticks_in_contact += 1


## Transition to CONTACTING when a new overlap is detected.
func begin_contact() -> void:
	phase = Phase.CONTACTING
	ticks_in_contact = 0


## Transition back to SEPARATED when the gap exceeds the separation epsilon.
func end_contact() -> void:
	phase = Phase.SEPARATED
	ticks_in_contact = 0
	last_constraint_impulse = 0.0
	last_constraint_normal_x = 0.0
	last_constraint_normal_y = 0.0


func is_new_contact() -> bool:
	return phase == Phase.CONTACTING and ticks_in_contact == 0


func is_persistent_contact() -> bool:
	return phase == Phase.CONTACTING and ticks_in_contact > 0
