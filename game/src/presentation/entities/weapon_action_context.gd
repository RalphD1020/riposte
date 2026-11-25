class_name WeaponActionContext
extends RefCounted
## WEAPON-PATH-004: the action in flight that the drawn sword depends on beside
## the blade's own pose, read from the snapshots — never new simulation state.
## The latched origin is `cut_dir` (a rebound does not change it); `committed`
## is the cut's turnover, stepped once per snapshot; `swing_started` and
## `transition` are presentation seconds, so a pose evaluated from this context
## is the same at any render rate.
##
## See also: /docs/concepts/presentation.md

var phase: CombatPhase.Id = CombatPhase.Id.NEUTRAL
var cut_dir: float = 1.0
## Travel through the commanded arc and the hold's charge, interpolated like
## the blade angle (`MatchPresenter.lift_inputs`).
var progress: float = 0.0
var charge: float = 0.0
var swing_charge: float = 0.0
var launch_preparation: float = 0.0
var committed: bool = false
var handling: WeaponHandlingProfile
## When the swing in flight launched, and when the drawn branch last changed;
## NAN out of a swing / before the first boundary.
var swing_started: float = NAN
var transition: float = NAN


## Fill from `row` with the lift inputs `progress` / `charge` and the turnover;
## returns self. A sword contact is not part of it (CONTACT-PRESENTATION-001).
func read(row: PresentationFighter, at_progress: float, at_charge: float, turnover: bool) -> WeaponActionContext:
	phase = row.phase
	cut_dir = row.cut_dir
	progress = at_progress
	charge = at_charge
	swing_charge = row.swing_charge
	launch_preparation = row.launch_preparation
	committed = turnover
	handling = row.combatant_spec.handling if row.combatant_spec != null else null
	return self


## A cut in flight or recovering from one: the phases the turnover reads.
func is_cut() -> bool:
	return is_cut_phase(phase)


static func is_cut_phase(id: CombatPhase.Id) -> bool:
	return CombatPresentationField.is_swing(id) or id == CombatPhase.Id.RECOVERY
