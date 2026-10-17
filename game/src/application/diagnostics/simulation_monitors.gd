class_name SimulationMonitors
extends RefCounted

## Godot custom performance monitors for the live match: the contact
## pipeline's cap counters and the cost of one authoritative step. They show in
## the editor debugger's Monitors tab and are readable through `Performance` in
## exported builds, so a release-build profile on a device sees the same
## numbers (CONTACT-MANIFOLD-001).
##
## The simulation cannot read a clock, so the step cost is measured around
## `DuelSimulation.step` by `MatchSession`. With no session every monitor
## reads 0.
##
## See also: /docs/concepts/combat.md
## See also: /docs/architecture/PERFORMANCE.md

const CCD_CAP_HITS := &"Riposte/CcdCapHits"
const CONTACT_CAP_HITS := &"Riposte/ContactCapHits"
const MAX_MANIFOLD_POINTS := &"Riposte/MaxManifoldPoints"
## The persistent-contact solver's two fallbacks, each on its own monitor so a
## regression names the cap it moved.
const REHOLD_BUDGET_EXHAUSTED := &"Riposte/ReholdBudgetExhausted"
const POSITION_GUARD_HITS := &"Riposte/PositionGuardHits"
## A real constraint one feature pair's manifold could not represent.
const MEANINGFUL_CONTACTS_DROPPED := &"Riposte/MeaningfulContactsDropped"
## A contact block whose exact solve reached its pivot cap.
const PIVOT_CAP_HITS := &"Riposte/PivotCapHits"
const GUARD_HARD_STOP_HITS := &"Riposte/GuardHardStopHits"
const SIM_STEP_US := &"Riposte/SimStepUs"
const ALL := [CCD_CAP_HITS, CONTACT_CAP_HITS, MAX_MANIFOLD_POINTS, REHOLD_BUDGET_EXHAUSTED, POSITION_GUARD_HITS, MEANINGFUL_CONTACTS_DROPPED, PIVOT_CAP_HITS, GUARD_HARD_STOP_HITS, SIM_STEP_US]

## The match being measured; the app points this at each session it composes.
var session: MatchSession


## Register every monitor, replacing any an earlier instance left behind.
func install() -> void:
	_register(CCD_CAP_HITS, ccd_cap_hits)
	_register(CONTACT_CAP_HITS, contact_cap_hits)
	_register(MAX_MANIFOLD_POINTS, max_manifold_points)
	_register(REHOLD_BUDGET_EXHAUSTED, rehold_budget_exhausted)
	_register(POSITION_GUARD_HITS, position_guard_hits)
	_register(MEANINGFUL_CONTACTS_DROPPED, meaningful_contacts_dropped)
	_register(PIVOT_CAP_HITS, pivot_cap_hits)
	_register(GUARD_HARD_STOP_HITS, guard_hard_stop_hits)
	_register(SIM_STEP_US, sim_step_us)


func uninstall() -> void:
	for id: StringName in ALL:
		if Performance.has_custom_monitor(id):
			Performance.remove_custom_monitor(id)
	session = null


func ccd_cap_hits() -> int:
	return session.simulation.diagnostics.ccd_cap_hits if session != null else 0


func contact_cap_hits() -> int:
	return session.simulation.diagnostics.contact_cap_hits if session != null else 0


func max_manifold_points() -> int:
	return session.simulation.diagnostics.max_manifold_points if session != null else 0


func rehold_budget_exhausted() -> int:
	return session.simulation.diagnostics.rehold_budget_exhausted if session != null else 0


func position_guard_hits() -> int:
	return session.simulation.diagnostics.position_guard_hits if session != null else 0


func meaningful_contacts_dropped() -> int:
	return session.simulation.diagnostics.meaningful_contacts_dropped if session != null else 0


func pivot_cap_hits() -> int:
	return session.simulation.diagnostics.pivot_cap_hits if session != null else 0


func guard_hard_stop_hits() -> int:
	return session.simulation.diagnostics.guard_hard_stop_hits if session != null else 0


func sim_step_us() -> int:
	return session.last_step_usec if session != null else 0


static func _register(id: StringName, reader: Callable) -> void:
	if Performance.has_custom_monitor(id):
		Performance.remove_custom_monitor(id)
	Performance.add_custom_monitor(id, reader)
