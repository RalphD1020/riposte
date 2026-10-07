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
## Contact directions, carried so feedback is directional without presentation
## guessing at the geometry. `NORMAL` is the way the impulse pushes; `STRIKE`
## is the way the contact point was travelling.
const NORMAL_X := "normal_x"
const NORMAL_Y := "normal_y"
const STRIKE_X := "strike_x"
const STRIKE_Y := "strike_y"
## Velocity change the impulse actually imparted (m/s), so a recoil can be
## shown at exactly the scale the simulation applied and never further.
const PUSH := "push"
## Bounded reading of how hard a blade clash was, for feedback channels that
## need a fraction rather than a class name.
const INTENSITY := "intensity"
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
## Swing semantics, carried so feedback and telemetry can say *why* a hit
## landed the way it did without re-deriving it (COMBAT-009). Diagnostic:
## none of these choose damage.
const SWING_POTENTIAL := "swing_potential"
const CONTACT_QUALITY := "contact_quality"
const EXPOSURE_FRACTION := "exposure_fraction"
## `SwingSemantics.Grade` as a label: what this hit *was*.
const GRADE := "grade"
## Structural coupling and the striking mass it produced (PHYS-002).
const COUPLING := "coupling"
const EFFECTIVE_MASS := "effective_mass"
## Kinetic severity in joules. Impulse rides on IMPULSE above (PHYS-004).
const SEVERITY := "severity"
## Normalized impulse × exposure: what stagger is decided from.
const STAGGER_PRESSURE := "stagger_pressure"
const CRITICAL := "critical"
## Whether this strike is an instant kill from the lethality law (COMBAT-011).
## True for unprotected THRUSTs and POKEs above the lethal severity threshold.
const LETHAL := "lethal"
const HEALTH := "health"
## Stamina shock applied on a damage event (STAMINA-001).
const STAMINA := "stamina"
## Thrust classification (COMBAT-010). Carried on body-contact events that
## qualify as a point-first thrust.
const THRUST_ALIGNMENT := "thrust_alignment"
const INCIDENCE_QUALITY := "incidence_quality"
## Contact kind: "slash", "thrust", or "graze". Present on all body contacts.
const CONTACT_KIND := "contact_kind"
## Tick fraction the contact occurred at, in [0, 1]. Trade attribution orders
## by this, so a strike that landed first wins regardless of slot.
const TOI := "toi"
## Staggered: duration in ticks.
const TICKS := "ticks"

## Contact saturated: how many contacts were resolved before the bound.
const COUNT := "count"

## Tangential sliding speed at contact, and the friction impulse applied to
## reduce it (PHYS-005). Carried on BODY_PUSH events.
const SLIDING_SPEED := "sliding_speed"
const TANGENTIAL_IMPULSE := "tangential_impulse"

## Burst started: which `MovementGestureState.BurstKind` was launched.
const BURST := "burst"
## The world heading the burst froze at launch. Carried so presentation can
## kick dust the right way without re-deriving the duel basis for itself.
const HEADING_X := "heading_x"
const HEADING_Y := "heading_y"

## Round and match flow (round_started, round_ended, match_ended, bind_ended).
const ROUND := "round"
const ROUNDS := "rounds"
const WINNER := "winner"
const REASON := "reason"
const SCORE_0 := "score_0"
const SCORE_1 := "score_1"

## Simulation fault: the StateInvariants id that failed.
const INVARIANT := "invariant"
