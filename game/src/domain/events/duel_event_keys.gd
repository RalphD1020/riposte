class_name DuelEventKeys
extends RefCounted

## Payload keys of DuelEvent.data, shared by the simulation (writers) and
## every reader (presentation, CPU, tutorial, summary, tests), so a misspelt
## key is a parse error instead of a silent zero. Values are plain Strings
## because payloads serialize to JSON for replays and analytics.
##
## See also: /docs/concepts/simulation.md

## Contact point on the arena plane (blade, body, parry, bind, kill).
const X := "x"
const Y := "y"

## Attack flow (attack_started, charge_started, attack_released, attack_whiffed).
const DIRECTION := "direction"
const CHARGE := "charge"
const ARC := "arc"

## Blade contact (blade_collision, bind_started).
const CLOSING_SPEED := "closing_speed"
const IMPULSE := "impulse"
## ContactResolver.CLASS_LIGHT / CLASS_SOLID / CLASS_STRONG.
const CONTACT_CLASS := "class"
const DEFLECTED_0 := "deflected_0"
const DEFLECTED_1 := "deflected_1"
const DELTA_0 := "delta_0"
const DELTA_1 := "delta_1"

## Parry: how much sooner (s) the defender threatens.
const MARGIN := "margin"

## Body strike (body_hit, critical_hit), from StrikeResult.
const DAMAGE := "damage"
const QUALITY := "quality"
const PHYSICAL_QUALITY := "physical_quality"
const EXPOSURE := "exposure"
const BLADE_FRACTION := "blade_fraction"
const ALIGNMENT := "alignment"
const CRITICAL := "critical"
const HEALTH := "health"
## Staggered: duration in ticks.
const TICKS := "ticks"

## Round and match flow (round_started, round_ended, match_ended, bind_ended).
const ROUND := "round"
const ROUNDS := "rounds"
const WINNER := "winner"
const REASON := "reason"
const SCORE_0 := "score_0"
const SCORE_1 := "score_1"
