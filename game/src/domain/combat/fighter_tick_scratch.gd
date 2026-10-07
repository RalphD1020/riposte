class_name FighterTickScratch
extends RefCounted

## Per-tick transient motor exertion and contact accumulation. Owned by
## DuelSimulation, one instance per fighter, reset at tick start. Systems
## write into it; the stamina step reads it once at tick end.
##
## This is NOT persisted, hashed, or replayed. It is the physical work
## ledger for one tick — the bridge between "how hard did the motors push"
## and "how much stamina did that cost." Static vars on system classes are
## the wrong ownership (fighter A overwrites fighter B's value); a scratch
## per fighter solves that without per-tick allocation.
##
## Motor work quantities are in simulation units (Newton-metres × rad/s × dt
## for rotational, Newtons × m/s × dt for linear). Phase 4 normalizes them
## against PhysicalBaseline calibration quantities before combining into
## stamina drain.
##
## Implements: /spec/invariants.md#stamina-001
## See also: /docs/concepts/combat.md

## Movement motor (linear).
## positive_work: energy driving motion (F·v > 0), integrated over dt.
## braking_work: energy opposing motion (F·v < 0, stored as positive).
## utilization: how hard the motor is pushing relative to capacity [0, 1].
var movement_positive_work: float = 0.0
var movement_braking_work: float = 0.0
var movement_utilization: float = 0.0

## Turn motor (body rotation about vertical axis).
var turn_positive_work: float = 0.0
var turn_braking_work: float = 0.0
var turn_utilization: float = 0.0

## Weapon motor (sword rotation about fighter pivot).
var weapon_positive_work: float = 0.0
var weapon_braking_work: float = 0.0
var weapon_utilization: float = 0.0

## Whether a burst is active this tick. Burst exertion is captured through the
## movement motor (burst force × burst velocity is naturally high), so this
## flag is context for Phase 4 tuning, not a separate cost channel.
var burst_active: bool = false

## Cumulative stamina shock from contacts resolved during this tick's
## chronological contact loop. Written by ContactResolver in Phase 4;
## zeroed here because contacts are part of the tick's accounting.
var contact_shock: float = 0.0


func reset() -> void:
	movement_positive_work = 0.0
	movement_braking_work = 0.0
	movement_utilization = 0.0
	turn_positive_work = 0.0
	turn_braking_work = 0.0
	turn_utilization = 0.0
	weapon_positive_work = 0.0
	weapon_braking_work = 0.0
	weapon_utilization = 0.0
	burst_active = false
	contact_shock = 0.0
