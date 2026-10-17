class_name ContactReading
extends RefCounted

## What a steel contact was, read from its own solve (CONTACT-OUTCOME-001):
## a description, never a decision. Nothing in the simulation reads it back;
## it changes no impulse and awards no recovery, exposure or winner.
##
## A contact that met a cut (the event names an attacker) is read by what it
## did to that cut's progress `θ̇·dir`:
## - GLANCE: the cut kept at least `GLANCE_KEPT` of its progress — redirected
##   rather than stopped.
## - CLASH: it lost more than that, was stopped, or was turned back.
## A contact between two blades neither (or both) of which was cutting:
## - CLASH: the solve changed either blade's θ̇ by at least its wielder's
##   `control_speed` — the speed a sword is under control below, so the
##   contact changed what that blade can do next.
## - TOUCH: anything smaller.
##
## This is not `ContactResolver.classify`. That `class` is the clang's
## closing-speed band (`light` / `solid` / `strong`). A glance can be `solid`.
## A parry and a deflection are their own events, decided by the resolver
## and the weapon system; a bind is a contact the manifold keeps holding.
## (Friction saturation does not separate them: steel on steel at μ = 0.2
## slides at its cone's limit in most first impacts, clash or glance.)
##
## See also: /docs/concepts/combat.md

const TOUCH := &"touch"
const GLANCE := &"glance"
const CLASH := &"clash"
## The share of its progress a cut keeps through a glance: more of the cut
## survived the contact than it lost. On the audit corpus (rules 53, Hard v
## Medium) about a fifth of contacts that met a cut kept more than half;
## nearly half were stopped or turned back.
const GLANCE_KEPT := 0.5


## The reading of one `BLADE_CONTACT` event, for weapons whose control
## speeds are `control_0` and `control_1` (rad/s).
static func classify(event: DuelEvent, control_0: float, control_1: float) -> StringName:
	if event.actor >= 0:
		var before := event.number(DuelEventKeys.PROGRESS_BEFORE)
		if before > 0.0 and event.number(DuelEventKeys.PROGRESS_AFTER) >= GLANCE_KEPT * before:
			return GLANCE
		return CLASH
	return CLASH if is_meaningful(event, control_0, control_1) else TOUCH


## Whether the contact changed either blade's θ̇ by at least its control speed.
static func is_meaningful(event: DuelEvent, control_0: float, control_1: float) -> bool:
	return absf(event.number(DuelEventKeys.DELTA_0)) >= control_0 or absf(event.number(DuelEventKeys.DELTA_1)) >= control_1
