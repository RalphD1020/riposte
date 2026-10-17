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
## is only bounded. The representative ship corpus expects zero of each but
## `rehold_budget_exhausted`, which it accepts only as the characterized class
## within its measured baseline (CONTACT-REHOLD-FALLBACK-001). A budget is
## never raised to make a counter read zero.
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
## Each exhausted tick, characterized (CONTACT-REHOLD-FALLBACK-001): its tick,
## how many distinct contact identities its re-holds held, and the least
## normal impulse any of them solved. One identity and a positive least
## impulse is one persistent contact genuinely closing again and again — the
## fast-rotation class the contract accepts; anything else is not that class.
var rehold_fallback_ticks := PackedInt32Array()
var rehold_fallback_identities := PackedInt32Array()
var rehold_fallback_least_impulse := PackedFloat64Array()
## Degenerate pins in the position stage: a pass scaled down by
## `RigidContactSolver.TURN_GUARD`, or an overlap with no consistent correction
## (exactly opposed rows), left in place so no hard row is broken. A contact's
## own correction bound, `contact_max_correction`, is a correction rate, not a
## cap: a deep overlap is simply cleared over passes.
var position_guard_hits: int = 0
## Real constraints left out (TWO-POINT-001): sweeps that recorded the blades
## touching in a third constraint distinct from both points the manifold kept
## (`SwordContactGeometry.dropped_within`). Two convex blades touch at no more
## than two, so this counts only what takes the blades deeply crossed. The
## representative ship corpus expects zero.
var meaningful_contacts_dropped: int = 0
## Contact blocks whose exact solve reached `ContactLcp.MAX_PIVOTS` (the block
## then applies nothing).
var pivot_cap_hits: int = 0
## Guard-limit fallback (GUARD-LIMIT-SOFT-001): a tick whose hard stop removed
## outward speed the soft zone had not bled down to one tick of wind-up, or
## found the blade already past the limit. The resting wind-up's own push
## into a stop it already occupies is not counted. Never hashed.
var guard_hard_stop_hits: int = 0


func reset() -> void:
	ccd_cap_hits = 0
	contact_cap_hits = 0
	max_manifold_points = 0
	rehold_budget_exhausted = 0
	rehold_fallback_ticks.clear()
	rehold_fallback_identities.clear()
	rehold_fallback_least_impulse.clear()
	position_guard_hits = 0
	meaningful_contacts_dropped = 0
	pivot_cap_hits = 0
	guard_hard_stop_hits = 0


## One exhausted tick's characterization (see `rehold_fallback_ticks`).
func record_rehold_fallback(tick: int, identities: int, least_impulse: float) -> void:
	rehold_fallback_ticks.append(tick)
	rehold_fallback_identities.append(identities)
	rehold_fallback_least_impulse.append(least_impulse)


func observe_manifold(manifold: SwordContactSet) -> void:
	max_manifold_points = maxi(max_manifold_points, manifold.point_count)
