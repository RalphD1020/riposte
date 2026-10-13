class_name ContactDiagnostics
extends RefCounted

## Counters for the contact pipeline's fixed caps (CONTACT-MANIFOLD-001).
##
## Every cap — CCD substeps, contacts per tick, points per feature pair, solver
## iterations and pivots — is fixed, so a pathological frame never buys itself more work.
## When one is reached the simulation takes its deterministic fallback and
## counts it here, so an overflow is visible instead of silent. Nothing in the
## simulation reads these back; they are never hashed and never decide play.
##
## Each cap keeps its own counter. They mean different things — a sweep that
## needed more substeps, a tick that ran out of contacts, a held contact that
## re-crossed too often, a degenerate pin — and one summed number would hide
## which one a regression moved. (An illegal state is not a counter at all: it
## ends the match as `SIMULATION_FAULT`.)
##
## Policy: every fallback is legal (deterministic, and the overlap bounds still
## hold on the tick it fires), so adversarial and fuzz play may reach one and
## is only bounded. The representative ship corpus expects zero of each. A
## budget is never raised to make a counter read zero.
##
## See also: /docs/concepts/combat.md

## Sweeps whose motion wanted more substeps than `max_substeps` allows.
var ccd_cap_hits: int = 0
## Ticks whose chronological loop reached `max_contacts_per_tick`.
var contact_cap_hits: int = 0
## Most contact points (all feature pairs together) any tick has carried.
var max_manifold_points: int = 0
## Persistent contact (RIGID-CONTACT-001): ticks whose mid-tick re-holds used
## all of `RigidContactSolver.HOLDS_PER_TICK` (the position stage then clears
## what is left).
var rehold_budget_exhausted: int = 0
## Degenerate pins in the position stage: a pass scaled down by
## `RigidContactSolver.TURN_GUARD`, or an overlap with no consistent correction
## (exactly opposed rows), left in place so no hard row is broken. A contact's
## own correction bound, `contact_max_correction`, is a correction rate, not a
## cap: a deep overlap is simply cleared over passes.
var position_guard_hits: int = 0
## Real constraints left out (TWO-POINT-001): feature pairs, over every
## recorded sweep, that touched in a third constraint distinct from both points
## their own manifold kept (`SwordContactGeometry.dropped_within`). Every
## feature pair keeps its own two points, so a hilt lock's three constraints
## are all solved; this counts only what one convex feature pair cannot
## represent, which takes two features deeply crossed. The representative ship
## corpus expects zero, for every feature.
var meaningful_contacts_dropped: int = 0
## Contact blocks whose exact solve reached `ContactLcp.MAX_PIVOTS` (the block
## then applies nothing).
var pivot_cap_hits: int = 0


func reset() -> void:
	ccd_cap_hits = 0
	contact_cap_hits = 0
	max_manifold_points = 0
	rehold_budget_exhausted = 0
	position_guard_hits = 0
	meaningful_contacts_dropped = 0
	pivot_cap_hits = 0


func observe_manifold(manifold: SwordContactSet) -> void:
	max_manifold_points = maxi(max_manifold_points, manifold.point_count)
