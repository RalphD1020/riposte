class_name ConditionModel
extends RefCounted

## Physical capability (CONDITION-001, rules 45; STAMINA-004, rules 53). One
## damage fraction feeds three linear ranges, each with its own authored
## floor, and start-of-tick stamina feeds the force term alone:
##
## ```text
## h              = clamp(health / max_health, 0, 1)
## fatigue        = Fs + (1 − Fs)·s            Fs = stamina_force_floor
## force_scale    = (F + (1 − F)·h) · fatigue  F  = condition_force_floor     (0.70)
## speed_scale    = S + (1 − S)·h              S  = condition_speed_floor     (0.85)
## tracking_scale = T + (1 − T)·h              T  = condition_tracking_floor  (0.80)
## ```
##
## Strictly linear in each input, exactly 1 at full health and full stamina
## (the span is the floor's complement, so the identity holds by
## construction), and approaching each floor only at zero. Stamina never
## touches speed ceilings, tracking or input timing. It does scale brake
## force, so a tired blade takes longer to stop. The same law applies to
## every fighter, from their own actuators.
##
## Implements: /spec/invariants.md#condition-001
## Implements: /spec/invariants.md#stamina-004
## See also: /docs/concepts/combat.md


## Write `out` for a fighter at `health` of `max_health` with start-of-tick
## `stamina` under `combat`'s floors and costs, and return it.
static func compute(health: float, max_health: float, stamina: float, combat: CombatTuning, out: ConditionState) -> ConditionState:
	var h := SimMath.clamp01(health / max_health) if max_health > 0.0 else 0.0
	var s := SimMath.clamp01(stamina)
	out.health_fraction = h
	out.damage_fraction = 1.0 - h
	out.stamina = s
	out.fatigue_scale = _linear(combat.stamina_force_floor, s)
	out.damage_force_scale = _linear(combat.condition_force_floor, h)
	out.force_scale = out.damage_force_scale * out.fatigue_scale
	out.speed_scale = _linear(combat.condition_speed_floor, h)
	out.tracking_scale = _linear(combat.condition_tracking_floor, h)
	out.can_dash = StaminaModel.can_dash(s, combat)
	out.can_charge = StaminaModel.can_charge(s)
	return out


## `fighter`'s condition under `rules`, freshly computed — for readers outside
## the tick (threat estimates, the CPU, the snapshot). Inside the tick systems
## read the frozen state in their scratch instead.
static func of(fighter: FighterState, rules: DuelRules) -> ConditionState:
	return compute(fighter.health, rules.spec_of(fighter).fighter.max_health, fighter.stamina, rules.combat, ConditionState.new())


static func _linear(floor_value: float, h: float) -> float:
	return floor_value + (1.0 - floor_value) * h
