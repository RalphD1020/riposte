class_name CpuDecisionTrace
extends RefCounted

## Structured trace of one CPU decision (Phase 8a). Fixed typed fields,
## not dictionaries, so telemetry and future ML pipelines read a stable
## schema. Separate from DuelEvent — authoritative gameplay events stay
## clean; these are a diagnostic sidecar.
##
## See also: /docs/concepts/cpu.md, /docs/architecture/ml-readiness.md

## Tick at which this decision was made.
var tick: int = 0
## Tick of the observation the decision used (proves perception delay).
var observation_tick: int = 0
## Move utility scores: [HOLD, APPROACH, RETREAT, ORBIT, BAIT].
var move_scores: PackedFloat64Array = PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
## Chosen footwork and attack.
var chosen_move: CpuController.Move = CpuController.Move.HOLD
var chosen_attack: CpuController.Attack = CpuController.Attack.NONE
## Tactical assessment summary (compact scalar snapshot).
var measure_quality: float = 0.0
var initiative: float = 0.0
var stamina_depletion: float = 0.0
var tempo_opportunity: float = 0.0
var arena_pressure: float = 0.0
## Whether a burst was started on this decision.
var burst_started: bool = false
var burst_is_lateral: bool = false
## Edge awareness fields for future ML corpus.
var edge_clearance: float = 0.0
var outward_radial_speed: float = 0.0
var stopping_margin: float = 0.0
var voluntary_ring_out_risk: bool = false
## Push-pressure awareness (CPU-007).
var body_contact_active: bool = false
var push_pressure: float = 0.0
var being_displaced: bool = false
var time_to_support_loss: int = 2147483647


const MOVE_COUNT := 5
const ATTACK_COUNT := 3


static func create(
	decision_tick: int,
	seen_tick: int,
	utilities: PackedFloat64Array,
	move: CpuController.Move,
	attack: CpuController.Attack,
	assessment: TacticalAssessment,
) -> CpuDecisionTrace:
	var trace := CpuDecisionTrace.new()
	trace.tick = decision_tick
	trace.observation_tick = seen_tick
	trace.move_scores = utilities.duplicate()
	trace.chosen_move = move
	trace.chosen_attack = attack
	trace.measure_quality = assessment.measure_quality
	trace.initiative = assessment.initiative
	trace.stamina_depletion = assessment.stamina_depletion
	trace.tempo_opportunity = assessment.tempo_opportunity
	trace.arena_pressure = assessment.arena_pressure
	trace.edge_clearance = assessment.edge_clearance
	trace.outward_radial_speed = assessment.outward_radial_speed
	trace.stopping_margin = assessment.stopping_margin
	trace.body_contact_active = assessment.body_contact_active
	trace.push_pressure = assessment.push_pressure
	trace.being_displaced = assessment.being_displaced
	trace.time_to_support_loss = assessment.time_to_support_loss
	return trace
