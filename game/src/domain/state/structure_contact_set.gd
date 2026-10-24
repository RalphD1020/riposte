class_name StructureContactSet
extends RefCounted

## One sword's contact with the stage's structures (STRUCTURE-CONTACT-001):
## whether it touches, whether a touch is a new contact, where, and what each
## held point carried into the next tick. One set per fighter, present only
## when the rules have structures, so a stage without them hashes as before.
##
## The lifecycle is the sword pair's (SwordContactSet): a blade resting on
## stone must genuinely come off it, past `separation_epsilon`, before it can
## strike it again. Separation is geometry, never a timer.
##
## ```text
## SEPARATED  --gap <= 0------------------->  CONTACTING   (a new contact)
## CONTACTING --gap > 0-------------------->  SEPARATING
## SEPARATING --gap > separation_epsilon--->  SEPARATED
## SEPARATING --gap <= 0------------------->  CONTACTING   (not a new contact)
## ```
##
## A point's identity is its feature: which structure and which of its shapes
## (CONTACT-IDENTITY-001). A blade sliding along one arc keeps one identity
## the whole way, so its warm start survives the slide; moving onto a jamb is
## a different surface and starts cold. Storage slots are never identity.
##
## Implements: /spec/invariants.md#structure-contact-001
## See also: /docs/concepts/combat.md

enum Phase { SEPARATED, CONTACTING, SEPARATING }

## A blade meets at most two features at once (a wall and a jamb in a corner).
const CAPACITY := 2
const NO_FEATURE := -1

var phase: Phase = Phase.SEPARATED
var phase_ticks: int = 0
var point_count: int = 0
## Per point: the feature (`structure * SHAPES + shape`), the blade point
## touching, the normal from the structure toward the blade, the surface gap
## (≤ 0 touching), and where on the blade (0 at the base, 1 at the tip).
var feature := PackedInt32Array()
var point_x := PackedFloat64Array()
var point_y := PackedFloat64Array()
var point_nx := PackedFloat64Array()
var point_ny := PackedFloat64Array()
var gap := PackedFloat64Array()
var fraction := PackedFloat64Array()
## This tick's physical impulses at each point (N·s): a reading.
var normal_impulse := PackedFloat64Array()
var tangent_impulse := PackedFloat64Array()
## Warm start (RIGID-CONTACT-003): last tick's held impulses per feature.
## Carried state, hashed.
var hold_count: int = 0
var hold_feature := PackedInt32Array()
var hold_normal := PackedFloat64Array()
var hold_tangent := PackedFloat64Array()

## Most shapes one structure may have, for the feature encoding.
const SHAPES := 64


static func feature_of(structure: int, shape: int) -> int:
	return structure * SHAPES + shape


## The structure a feature belongs to.
static func structure_of(feature_id: int) -> int:
	return floori(float(feature_id) / float(SHAPES))


func _init() -> void:
	feature = _ints()
	hold_feature = _ints()
	point_x = _floats()
	point_y = _floats()
	point_nx = _floats()
	point_ny = _floats()
	gap = _floats()
	fraction = _floats()
	normal_impulse = _floats()
	tangent_impulse = _floats()
	hold_normal = _floats()
	hold_tangent = _floats()


static func _ints() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(CAPACITY)
	out.fill(NO_FEATURE)
	return out


static func _floats() -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(CAPACITY)
	out.fill(0.0)
	return out


func reset() -> void:
	phase = Phase.SEPARATED
	phase_ticks = 0
	point_count = 0
	clear_holds()


func clear_holds() -> void:
	hold_count = 0
	hold_feature.fill(NO_FEATURE)
	hold_normal.fill(0.0)
	hold_tangent.fill(0.0)


func set_phase(next: Phase) -> void:
	if next != phase:
		phase = next
		phase_ticks = 0


func tick() -> void:
	phase_ticks += 1


func is_persisted() -> bool:
	return phase != Phase.SEPARATED


## Start of a tick's search and of each substep that re-records: the set
## describes where the sword ends up touching.
func begin_search() -> void:
	point_count = 0
	normal_impulse.fill(0.0)
	tangent_impulse.fill(0.0)


## Advance the lifecycle from the sword's least gap to any structure. True only
## when this observation begins a new contact.
func observe(least_gap: float, separation_epsilon: float) -> bool:
	match phase:
		Phase.SEPARATED:
			if least_gap <= 0.0:
				set_phase(Phase.CONTACTING)
				return true
		Phase.CONTACTING:
			if least_gap > 0.0:
				set_phase(Phase.SEPARATING)
		Phase.SEPARATING:
			if least_gap <= 0.0:
				set_phase(Phase.CONTACTING)
			elif least_gap > separation_epsilon:
				set_phase(Phase.SEPARATED)
	return false


func record_point(index: int, feature_id: int, x: float, y: float, nx: float, ny: float, surface_gap: float, along: float) -> void:
	feature[index] = feature_id
	point_x[index] = x
	point_y[index] = y
	point_nx[index] = nx
	point_ny[index] = ny
	gap[index] = surface_gap
	fraction[index] = along


## The hold record of `feature_id`, or -1.
func hold_of(feature_id: int) -> int:
	for i in hold_count:
		if hold_feature[i] == feature_id:
			return i
	return -1
