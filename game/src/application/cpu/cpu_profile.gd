class_name CpuProfile
extends RefCounted

## CPU difficulty as data (PLAN Phase 9). Every profile plays by exactly the
## same rules through the same PlayerCommand; Hard is better only through
## faster (still human) reactions, sharper range judgment, and stronger
## tactical weights — never faster turning, faster attacks, hidden damage, or
## future input.
##
## See also: /docs/concepts/cpu.md

var difficulty: MatchConfig.Difficulty = MatchConfig.Difficulty.MEDIUM
## Perception delay for the opponent (own weapon is felt directly).
var reaction_ticks: int = 0
var decision_ticks: int = 0
var decision_jitter: int = 0
## Uniform error (m) applied to perceived distance at each decision.
var range_error: float = 0.0
## How fully the delayed sighting is extrapolated by observed velocity
## (0 = reacts to where the opponent was, 1 = reads their motion).
var anticipation: float = 0.0
## Preferred distances (m) between fighter centers.
var engage_range: float = 0.0
var tap_range: float = 0.0
var charge_range: float = 0.0
var release_slack: float = 0.0
## Tactical weights.
var aggression: float = 0.0
var retreat_weight: float = 0.0
## Urge to step back out of smothered measure (COMBAT §31).
var spacing_weight: float = 0.0
var angle_weight: float = 0.0
var punish_weight: float = 0.0
var intercept_weight: float = 0.0
var bait_weight: float = 0.0
var charge_weight: float = 0.0
## Value of probing a neutral opponent from good range.
var probe_weight: float = 0.0
## Value of acting on initiative: attack when threatening first, step out
## when the opponent threatens first (COMBAT §46).
var initiative_weight: float = 0.0
## Urge to act that builds during a standoff (prevents stalemates).
var pressure_weight: float = 0.0
var attack_threshold: float = 0.0
## Charge target range; Easy overcharges.
var charge_min: float = 0.0
var charge_max: float = 0.0
## Easy releases regardless of range (poor range discipline).
var release_any_range: bool = false


static func for_difficulty(level: MatchConfig.Difficulty) -> CpuProfile:
	match level:
		MatchConfig.Difficulty.EASY:
			return easy()
		MatchConfig.Difficulty.HARD:
			return hard()
	return medium()


## Delayed reactions, poor range, overcharges, weak punish awareness,
## predictable rhythm.
static func easy() -> CpuProfile:
	var profile := CpuProfile.new()
	profile.difficulty = MatchConfig.Difficulty.EASY
	profile.reaction_ticks = 22
	profile.decision_ticks = 12
	profile.decision_jitter = 0
	profile.range_error = 0.45
	profile.anticipation = 0.0
	profile.engage_range = 1.4
	profile.tap_range = 1.15
	profile.charge_range = 1.6
	profile.release_slack = 0.6
	profile.aggression = 0.9
	profile.retreat_weight = 0.15
	profile.spacing_weight = 0.0
	profile.angle_weight = 0.0
	profile.punish_weight = 0.1
	profile.intercept_weight = 0.0
	profile.bait_weight = 0.0
	profile.charge_weight = 0.9
	profile.probe_weight = 0.2
	profile.initiative_weight = 0.0
	profile.pressure_weight = 0.3
	profile.attack_threshold = 0.25
	profile.charge_min = 0.85
	profile.charge_max = 1.0
	profile.release_any_range = true
	return profile


## Sensible range, varied charge, basic whiff punishment, occasional angles.
static func medium() -> CpuProfile:
	var profile := CpuProfile.new()
	profile.difficulty = MatchConfig.Difficulty.MEDIUM
	profile.reaction_ticks = 13
	profile.decision_ticks = 6
	profile.decision_jitter = 2
	profile.range_error = 0.18
	profile.anticipation = 0.6
	profile.engage_range = 1.6
	profile.tap_range = 1.2
	profile.charge_range = 1.8
	profile.release_slack = 0.25
	profile.aggression = 0.75
	profile.retreat_weight = 0.7
	profile.spacing_weight = 0.5
	profile.angle_weight = 0.35
	profile.punish_weight = 0.6
	profile.intercept_weight = 0.4
	profile.bait_weight = 0.0
	profile.charge_weight = 0.5
	profile.probe_weight = 0.4
	profile.initiative_weight = 0.2
	profile.pressure_weight = 0.4
	profile.attack_threshold = 0.35
	profile.charge_min = 0.2
	profile.charge_max = 0.7
	return profile


## Baits, steps outside committed swings, intercepts charges with taps,
## punishes poor blade position, varies rhythm, respects range.
static func hard() -> CpuProfile:
	var profile := CpuProfile.new()
	profile.difficulty = MatchConfig.Difficulty.HARD
	profile.reaction_ticks = 8
	profile.decision_ticks = 3
	profile.decision_jitter = 3
	profile.range_error = 0.05
	profile.anticipation = 0.9
	profile.engage_range = 1.75
	profile.tap_range = 1.2
	profile.charge_range = 1.75
	profile.release_slack = 0.1
	profile.aggression = 0.7
	profile.retreat_weight = 1.0
	profile.spacing_weight = 0.8
	profile.angle_weight = 0.9
	profile.punish_weight = 1.2
	profile.intercept_weight = 1.0
	profile.bait_weight = 0.6
	profile.charge_weight = 0.45
	profile.probe_weight = 0.2
	profile.initiative_weight = 0.7
	profile.pressure_weight = 0.35
	profile.attack_threshold = 0.4
	profile.charge_min = 0.15
	profile.charge_max = 0.6
	return profile
