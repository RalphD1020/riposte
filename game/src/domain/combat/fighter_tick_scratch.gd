class_name FighterTickScratch
extends RefCounted

## Per-tick transient values for one fighter, owned by DuelSimulation (one
## instance per fighter, so fighter A never overwrites fighter B's value, and
## nothing is allocated per tick). Every field is overwritten each tick before
## it is read.
##
## This is NOT persisted, hashed, or replayed.
##
## See also: /docs/concepts/combat.md

## Reused pose for sampling the weapon coordinate's inertia each tick (never
## read across ticks, so nothing here needs resetting).
var motor_pose := BladePose.new()

## This fighter's condition for the tick (CONDITION-001, STAMINA-004), frozen
## once from start-of-tick health and stamina by `DuelSimulation` before any
## motor runs. Every motor reads it; nothing recomputes it mid-tick.
## Overwritten each tick.
var condition := ConditionState.new()

## The motors' own state at the start of the tick, before any motor or
## contact, and the stamina their work cost this tick (STAMINA-004).
## Overwritten each tick by `DuelSimulation`; contact impulses never enter.
var start_vx: float = 0.0
var start_vy: float = 0.0
var start_turn_rate: float = 0.0
var exertion: float = 0.0
var dashed: bool = false

## The blade's angular speed (rad/s) at the start of the tick, before any
## motor or contact. The arrest law reads it (RIGID-CONTACT-002): a cut held
## under control that gained nothing over the tick is pinned. Overwritten
## each tick by `DuelSimulation`.
var weapon_start_speed: float = 0.0
## Set when this tick's steel episode dipped impact authority, so the same
## tick does not also recover it (IMPACT-AUTHORITY-001). Cleared at tick start.
var authority_dipped: bool = false
