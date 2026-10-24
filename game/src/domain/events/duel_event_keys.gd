class_name DuelEventKeys
extends RefCounted

## Payload keys of DuelEvent.data, shared by the simulation (writers) and
## every reader (presentation, CPU, tutorial, summary, tests), so a misspelt
## key is a parse error instead of a silent zero. Values are plain Strings
## because payloads serialize to JSON for replays and analytics.
##
## See also: /docs/concepts/simulation.md

## Contact point on the arena plane (blade, body, parry, kill).
const X := "x"
const Y := "y"

## Attack flow (attack_started, charge_started, attack_released, attack_whiffed).
const DIRECTION := "direction"
const CHARGE := "charge"
const ARC := "arc"

## Blade contact (blade_contact).
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
## Energy the contact dissipated (J, ContactMechanics): the size of what
## actually happened, for feedback that must not read charge.
const ENERGY := "energy"
## Where on each blade a blade contact landed (0 crossguard, 1 tip).
const FRACTION_0 := "fraction_0"
const FRACTION_1 := "fraction_1"
## Which steel the contact was named by (`SwordContactSet.PAIR_*`): blade on
## blade, or a blade on a guard root.
const STEEL_PAIR := "steel_pair"
## How many manifold points a sword contact was solved on.
const POINT_COUNT := "point_count"
## A structure contact: which structure (index in `DuelRules.structures`) and
## which feature of it (`StructureContactSet.feature_of`) took the most impulse.
const STRUCTURE := "structure"
const FEATURE := "feature"
## The two surfaces of a structure contact, the materials the solver already
## resolved (`ContactPair`). Order is not meaningful: audio sorts them. These
## name the surfaces; they are not a sound.
const MATERIAL_0 := "material_0"
const MATERIAL_1 := "material_1"
## ContactResolver.CLASS_LIGHT / CLASS_SOLID / CLASS_STRONG.
const CONTACT_CLASS := "class"
## Whether each side's cut was arrested by the contact (RIGID-CONTACT-002).
const ARRESTED_0 := "arrested_0"
const ARRESTED_1 := "arrested_1"
## Each side's weapon-speed change from the solve (rad/s).
const DELTA_0 := "delta_0"
const DELTA_1 := "delta_1"
## The attack's progress `θ̇·dir` before and after the solve (rad/s), when a
## cut met steel (ContactOutcome): how much of the cut the contact let through.
const PROGRESS_BEFORE := "progress_before"
const PROGRESS_AFTER := "progress_after"
## The impulse fighter 0's sword received, summed over the rows (N·s);
## fighter 1's is its negative (CONTACT-OUTCOME-001).
const IMPULSE_X := "impulse_x"
const IMPULSE_Y := "impulse_y"
## The fastest closing over the rows after the solve (m/s); negative is
## separating.
const CLOSING_AFTER := "closing_after"
## The largest share of its friction cone any row used (1 is sliding).
const FRICTION_SATURATION := "friction_saturation"

## Parry: the riposte advantage — how much sooner (s) the defender threatens
## than the attacker in the state the interception left. A reading, never the
## parry's definition; zero or negative is a parry that won no tempo.
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
## Structural coupling (PHYS-002) and the contact's effective mass `1/k` (kg,
## IMPACT-PHYSICS-001): how heavy the strike was where it landed.
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
## Thrust classification (COMBAT-010). Carried on body-contact events that
## qualify as a point-first thrust.
const THRUST_ALIGNMENT := "thrust_alignment"
## Which vulnerable region a BODY_HIT struck. Rules 55: only `REGION_TORSO`.
const REGION := "region"
const REGION_TORSO := "torso"
const INCIDENCE_QUALITY := "incidence_quality"
## Contact kind. Values are `StrikeResult.KIND_*` (slash, poke, thrust, graze).
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

## Round and match flow (round_started, round_ended, match_ended).
const ROUND := "round"
const ROUNDS := "rounds"
const WINNER := "winner"
const REASON := "reason"
const SCORE_0 := "score_0"
const SCORE_1 := "score_1"

## Simulation fault: the StateInvariants id that failed.
const INVARIANT := "invariant"

## Ring-out: position and velocity at the moment the center crossed the edge.
const POSITION_X := "position_x"
const POSITION_Y := "position_y"
const VELOCITY_X := "velocity_x"
const VELOCITY_Y := "velocity_y"
