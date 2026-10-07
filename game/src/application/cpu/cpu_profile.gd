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
## How far outside reach a charged swing may be released. A swing takes time
## to travel, so this is a *lead* allowance, not sloppiness: a fighter who
## waits until the opponent is already inside reach releases late and arrives
## after they have moved on. A profile may only afford a generous lead if it
## knows where the opponent really is, which is why this rises with accuracy
## rather than falling with it.
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
## Weight of point-threat awareness: how much the CPU respects an opponent
## whose sword tip is aimed at it with forward motion (COMBAT-010).
var point_threat_weight: float = 0.0
## Chance a decisive approach or retreat is committed as a dash instead of a
## step. A difficulty axis that costs the CPU nothing it is not entitled to:
## the gesture goes out on its command stream and is read by the same
## recognizer a thumb drives, so a dashing CPU is a CPU using the input
## language better, not one with a better body.
var burst_weight: float = 0.0
## Charge target range; Easy overcharges.
var charge_min: float = 0.0
var charge_max: float = 0.0
## Easy releases regardless of range (poor range discipline).
var release_any_range: bool = false
## HEMA-derived tactical weights (Phase 6). All difficulties share the same
## evaluator; these weights decide how much each signal matters.
## How aggressively to press an opponent near the arena edge.
var corner_pressure_weight: float = 0.0
## How strongly to exploit tempo (punish recovery/overswing windows).
var tempo_awareness: float = 0.0
## How reliably to retreat or side-step after own committed attack.
var withdrawal_discipline: float = 0.0
## Weight for lateral (clockwise/counterclockwise) burst evaluation.
var lateral_dash_weight: float = 0.0
## How much stamina cost weighs against action utility (STAMINA-001). 0 =
## ignore stamina entirely (overextend), higher = conserve more. The CPU
## computes expected stamina cost from the motor physics, not from authored
## action-specific constants.
var stamina_cost_weight: float = 0.0


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
	profile.point_threat_weight = 0.0
	## Easy never dashes. A gesture is an input skill, and this is the profile
	## that does not have one.
	profile.burst_weight = 0.0
	profile.charge_min = 0.85
	profile.charge_max = 1.0
	profile.release_any_range = true
	## Easy does not read tactical context beyond the basics.
	profile.corner_pressure_weight = 0.0
	profile.tempo_awareness = 0.0
	profile.withdrawal_discipline = 0.0
	profile.lateral_dash_weight = 0.0
	## Easy ignores stamina and overextends.
	profile.stamina_cost_weight = 0.0
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
	profile.point_threat_weight = 0.3
	profile.burst_weight = 0.07
	profile.charge_min = 0.2
	profile.charge_max = 0.7
	## Medium reads tempo and starts to exploit corners, but rarely
	## commits the lateral dash and does not disengage after attacking.
	profile.corner_pressure_weight = 0.2
	profile.tempo_awareness = 0.3
	profile.withdrawal_discipline = 0.1
	profile.lateral_dash_weight = 0.05
	## Medium starts conserving stamina.
	profile.stamina_cost_weight = 0.3
	return profile


## Baits, steps outside committed swings, intercepts charges with taps,
## punishes poor blade position, varies rhythm, respects range.
static func hard() -> CpuProfile:
	var profile := CpuProfile.new()
	profile.difficulty = MatchConfig.Difficulty.HARD
	profile.reaction_ticks = 8
	## Hard *perceives* faster; it does not fidget faster. Re-picking footwork
	## every few ticks is indecision, and in a momentum game indecision is
	## expensive twice over: the body never builds a coherent stride, and a
	## fighter who is always changing their own motion strikes with degraded
	## structural coupling (PHYS-002). Reaction latency is the difficulty
	## axis; decision churn is not.
	profile.decision_ticks = 5
	profile.decision_jitter = 2
	profile.range_error = 0.05
	profile.anticipation = 0.9
	profile.engage_range = 1.75
	profile.tap_range = 1.2
	profile.charge_range = 1.75
	profile.release_slack = 0.35
	profile.aggression = 0.7
	profile.retreat_weight = 1.0
	profile.spacing_weight = 0.8
	profile.angle_weight = 0.9
	profile.punish_weight = 1.2
	profile.intercept_weight = 1.0
	profile.bait_weight = 0.6
	profile.charge_weight = 0.45
	profile.probe_weight = 0.4
	profile.initiative_weight = 0.7
	profile.pressure_weight = 0.35
	## Hard's discipline already lives in where it stands and what it perceives:
	## strikes are gated on range quality, and it judges range accurately.
	## Demanding a *higher* score than Medium on top of that was caution counted
	## twice, and it showed up as a fighter who out-positioned opponents it
	## never got around to hitting.
	profile.attack_threshold = 0.35
	profile.point_threat_weight = 0.7
	## Hard closes and disengages explosively, because it knows where the
	## opponent is well enough to spend a committed dash on it. Still a
	## punctuation and not a gait: a dash overrides steering intent and spends
	## commitment, so dashing out of most decisive steps reads as twitchy and
	## costs more structure than the distance is worth.
	profile.burst_weight = 0.18
	## Hard picks its moments, and when it takes one it commits at least as
	## hard as Medium would. Charging *less* than a weaker profile was the one
	## place its sharper judgment worked against it: severity goes as `v²`, so
	## a timid ceiling capped its best strikes and cancelled out the
	## positional edge its reactions had earned.
	profile.charge_min = 0.2
	profile.charge_max = 0.8
	## Hard exploits tempo, presses corners, disengages deliberately, and
	## uses lateral dashes to exploit angles and evade point threats.
	profile.corner_pressure_weight = 0.6
	profile.tempo_awareness = 0.7
	profile.withdrawal_discipline = 0.5
	profile.lateral_dash_weight = 0.12
	## Hard spends deliberately — only when the expected gain justifies it.
	profile.stamina_cost_weight = 0.6
	return profile
