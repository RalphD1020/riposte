class_name ExposureModel
extends RefCounted

## Exposure as a reading of the physics (v36, COMBAT-009): how open a fighter
## is right now is how far behind their opponent they are in time-to-threat —
## their own readiness (weapon state, heading, the sweep onto the line,
## closing) against the opponent's actual threat from their geometry and
## kinematics (`InitiativeModel`).
##
## ```text
## margin   = T_threat(target) − T_threat(attacker)        (s; > 0 = target late)
## reading  = clamp01(0.5 + margin / (2·window))          0.5 = even initiative
## opening  = clamp01(margin / window)                     0 unless behind
## ```
##
## A fighter who whiffs is exposed because the opponent can physically hit
## first, never because a hidden number made their flesh softer. The reading
## feeds the CPU, telemetry, the HUD and presentation. It MUST NOT scale
## contact impulse, damage, stagger or criticals.
##
## Implements: /spec/invariants.md#combat-009
## See also: /docs/concepts/combat.md


## Seconds `target` is behind `attacker` in time-to-threat (positive = late).
static func margin(target: FighterState, attacker: FighterState, rules: DuelRules) -> float:
	return InitiativeModel.time_to_threat(target, attacker, rules) - InitiativeModel.time_to_threat(attacker, target, rules)


## `target`'s exposure to `attacker` in [0, 1]; 0.5 when initiative is even.
static func reading(target: FighterState, attacker: FighterState, rules: DuelRules) -> float:
	return reading_of(margin(target, attacker, rules), rules)


## The exposure a given `margin` (s, positive = late) reads as — for a caller
## that already holds both threat times and must not predict them twice.
static func reading_of(late: float, rules: DuelRules) -> float:
	return SimMath.clamp01(0.5 + late / (2.0 * rules.combat.exposure_window_seconds))


## How much of an opening `target` presents in [0, 1]: zero unless they are
## behind, one when they are a whole window behind.
static func opening(target: FighterState, attacker: FighterState, rules: DuelRules) -> float:
	return opening_of(margin(target, attacker, rules), rules)


## The opening a given `margin` (s, positive = late) reads as.
static func opening_of(late: float, rules: DuelRules) -> float:
	return SimMath.clamp01(late / rules.combat.exposure_window_seconds)
