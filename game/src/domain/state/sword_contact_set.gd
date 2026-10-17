class_name SwordContactSet
extends RefCounted

## The one authoritative record of sword-on-sword contact (COMBAT §43–§45,
## CONTACT-MANIFOLD-001): whether the swords are touching, whether a touch is a
## new contact, and where and how they touch.
##
## Steel is the two blades and each sword's guard root (STEEL-TOPOLOGY-001):
## three contact pairs — blade on blade, sword 0's blade on sword 1's guard,
## sword 0's guard under sword 1's blade — and never guard on guard. A guard
## pair exists only on the guard's protected side (GUARD-PROTECTION-001). The
## handle and the hands are not combat geometry (TORSO-CIRCLE-001). Each pair
## is two convex shapes, which touch at one
## point when they cross and at the two ends of their overlap when they lie
## along each other — never more — so each pair holds at most `POINTS_PER_PAIR`
## (two) points and the set `CAPACITY` (TWO-POINT-001). Every point carries its
## pair; identity never crosses pairs.
##
## Two swords that touch are not a sequence of independent strikes. A single
## clash lasts several ticks, and whether the next tick is "still that clash"
## or "a fresh one" is a real question with a real answer: the parts must
## genuinely come apart first. That lifecycle belongs to the sword pair:
##
## ```text
## SEPARATED  --gap <= touch-------------->  CONTACTING   (a new contact)
## CONTACTING --gap > touch--------------->  SEPARATING
## SEPARATING --gap > touch + epsilon----->  SEPARATED
## SEPARATING --gap <= touch-------------->  CONTACTING   (not a new contact)
## ```
##
## The epsilon is what makes this stable: a blade resting exactly on the touch
## distance would otherwise re-strike every tick. Separation is physical, a
## timer is not.
##
## Points are fixed capacity and stored compactly in the geometry's canonical
## order — by distance from each sword's origin — so nothing here allocates or
## iterates in an order the data does not fix.
##
## A point's index is a storage slot, never its identity (CONTACT-IDENTITY-001).
## Identity is geometric: the least movement of the point along both blades
## (`assign`), never the strong/middle/weak band its fraction falls in. One
## matcher decides it for everything that asks "is this the same contact as
## before?": the warm-start impulses, `persisted`, a point's `age` and its
## `contact_id`, which presentation keys sparks and scrape loops on. When one
## end of a line contact leaves, the survivor keeps its own history even though
## its slot changes.
##
## There is no bind phase: a bind is a contact that persists, solved every
## tick by `RigidContactSolver` (RIGID-CONTACT-002). The point geometry is a
## reading of this tick; its identity (`contact_id`, `age`) and the hold record
## carry from tick to tick, so they are hashed.
##
## Implements: /spec/invariants.md#combat-002
## Implements: /spec/invariants.md#contact-identity-001
## Implements: /spec/invariants.md#two-point-001
## Implements: /spec/invariants.md#steel-topology-001
## See also: /docs/concepts/combat.md

enum Phase {
	SEPARATED,
	CONTACTING,
	SEPARATING,
}

## The contact pairs: the two blades; sword 0's blade on sword 1's guard
## root; sword 0's guard root under sword 1's blade. Guard on guard is never a
## pair (STEEL-TOPOLOGY-001).
const PAIR_BLADES := 0
const PAIR_BLADE_ON_GUARD := 1
const PAIR_GUARD_ON_BLADE := 2
const PAIRS := 3
## Two convex shapes touch at one point when they cross, at the two ends of
## their overlap when they lie along each other — never more.
const POINTS_PER_PAIR := 2
const CAPACITY := PAIRS * POINTS_PER_PAIR
## The most a point may move along the two blades in one tick and still be the
## same contact: the sum of its fraction changes on each blade (0 at the
## crossguard, 1 at the point). Farther is a new point.
const MATCH_DISTANCE := 0.25
## No match (`assign`).
const UNMATCHED := -1

var phase: Phase = Phase.SEPARATED
## Ticks spent in the current phase (a reading: how long a contact has lasted).
var phase_ticks: int = 0

## Points touching this tick, `0..CAPACITY`.
var point_count: int = 0
## The normal the last first impact was named by, from sword 1 toward sword 0.
var normal_x: float = 0.0
var normal_y: float = 0.0
var point_x := PackedFloat64Array()
var point_y := PackedFloat64Array()
## Each point's contact pair (`PAIR_*`).
var pair := PackedInt32Array()
## Where along each blade the point lies: 0 at the blade's base, 1 at the
## point; a point on a guard reads 0 on that side, the base of its blade. Also
## the point's coordinate for identity (within its pair) and for presentation.
var fraction_a := PackedFloat64Array()
var fraction_b := PackedFloat64Array()
## Each point's own unit normal, from b toward a.
var point_nx := PackedFloat64Array()
var point_ny := PackedFloat64Array()
## Impulses the solver applied at each point this tick (N·s).
var normal_impulse := PackedFloat64Array()
var tangent_impulse := PackedFloat64Array()
## The point is the same contact (`assign`) as one touching last tick.
var persisted := PackedByteArray()
## A stable name for each point's contact, kept while `assign` matches it from
## tick to tick and new when it begins (> 0). Presentation's spark and scrape
## identity; never read by the simulation.
var contact_id := PackedInt32Array()
## Ticks the point's contact has lasted before this one (0 on its first tick).
var age := PackedInt32Array()

## The held-contact solver's physical impulses over the last tick, per sword
## row, with the blade fractions each row was solved at (RIGID-CONTACT-003).
## This is the warm start: the next tick's first velocity solve starts a row
## from the record `assign` matches it to — the same physical point, never
## whichever slot it lands in. Kept compact (slots `0..hold_count() − 1`,
## canonical order). Carried state, so it is hashed. Only the velocity stage
## writes it — never the position stage's pseudo-impulse.
var hold_active := PackedByteArray()
var hold_pair := PackedInt32Array()
var hold_fraction_a := PackedFloat64Array()
var hold_fraction_b := PackedFloat64Array()
var hold_normal := PackedFloat64Array()
var hold_tangent := PackedFloat64Array()
## How fast the row still slides after that solve (m/s) — a reading for
## presentation (scrape), never fed back.
var hold_slip := PackedFloat64Array()

## Next `contact_id` to hand out.
var next_contact_id: int = 1
## Each guard pair's side (`PAIR_BLADE_ON_GUARD`, then `PAIR_GUARD_ON_BLADE`),
## decided when it first touches and kept until it parts
## (GUARD-PROTECTION-001): 0 free, 1 protected (steel), 2 passing (the blade
## came from the grip side and goes on). Carried state, so it is hashed.
var guard_mode := PackedInt32Array([0, 0])

var _previous_count: int = 0
var _previous_pair := PackedInt32Array()
var _previous_a := PackedFloat64Array()
var _previous_b := PackedFloat64Array()
var _previous_id := PackedInt32Array()
var _previous_age := PackedInt32Array()
var _match := PackedInt32Array()
## `assign_pairs` scratch: one pair's points gathered (≤ `POINTS_PER_PAIR`).
var _pair_new := PackedInt32Array([0, 0])
var _pair_old := PackedInt32Array([0, 0])
var _pair_new_a := PackedFloat64Array([0.0, 0.0])
var _pair_new_b := PackedFloat64Array([0.0, 0.0])
var _pair_old_a := PackedFloat64Array([0.0, 0.0])
var _pair_old_b := PackedFloat64Array([0.0, 0.0])
var _pair_out := PackedInt32Array([0, 0])


func _init() -> void:
	contact_id = _ints(0)
	age = _ints(0)
	pair = _ints(PAIR_BLADES)
	hold_pair = _ints(PAIR_BLADES)
	_previous_pair = _ints(PAIR_BLADES)
	_previous_id = _ints(0)
	_previous_age = _ints(0)
	_match = _ints(UNMATCHED)
	point_x = _floats(0.0)
	point_y = _floats(0.0)
	fraction_a = _floats(0.0)
	fraction_b = _floats(0.0)
	point_nx = _floats(0.0)
	point_ny = _floats(1.0)
	normal_impulse = _floats(0.0)
	tangent_impulse = _floats(0.0)
	hold_fraction_a = _floats(0.0)
	hold_fraction_b = _floats(0.0)
	hold_normal = _floats(0.0)
	hold_tangent = _floats(0.0)
	hold_slip = _floats(0.0)
	_previous_a = _floats(0.0)
	_previous_b = _floats(0.0)
	persisted.resize(CAPACITY)
	persisted.fill(0)
	hold_active.resize(CAPACITY)
	hold_active.fill(0)


static func _ints(value: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(CAPACITY)
	out.fill(value)
	return out


static func _floats(value: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(CAPACITY)
	out.fill(value)
	return out


func reset() -> void:
	phase = Phase.SEPARATED
	phase_ticks = 0
	point_count = 0
	_previous_count = 0
	next_contact_id = 1
	guard_mode[0] = 0
	guard_mode[1] = 0
	for i in CAPACITY:
		contact_id[i] = 0
		age[i] = 0
		persisted[i] = 0
		clear_hold(i)


func clear_hold(index: int) -> void:
	hold_active[index] = 0
	hold_pair[index] = PAIR_BLADES
	hold_fraction_a[index] = 0.0
	hold_fraction_b[index] = 0.0
	hold_normal[index] = 0.0
	hold_tangent[index] = 0.0
	hold_slip[index] = 0.0


## Held rows recorded (the record is compact).
func hold_count() -> int:
	var held := 0
	for i in CAPACITY:
		if hold_active[i] == 1:
			held = i + 1
	return held


## The one rule for "the same contact point as before" (CONTACT-IDENTITY-001).
## Each of `new_count` new points (blade fractions `new_a`/`new_b`) is matched
## to at most one of `old_count` old points, one to one, into `out`
## (`UNMATCHED` for a new contact). A pair can match only within
## `MATCH_DISTANCE` of movement (`|Δfraction_a| + |Δfraction_b|`). Of every
## legal assignment — at most seven for two points — the one matching the most
## points wins, then the least total movement, then the first in a fixed order
## (identity before swap). The result never depends on which slot a point
## happened to occupy, and a mirror leaves every fraction, and so the
## assignment, unchanged.
static func assign(
	new_count: int, new_a: PackedFloat64Array, new_b: PackedFloat64Array,
	old_count: int, old_a: PackedFloat64Array, old_b: PackedFloat64Array,
	out: PackedInt32Array
) -> void:
	for i in new_count:
		out[i] = UNMATCHED
	if new_count == 0 or old_count == 0:
		return
	var n1 := 1 if new_count > 1 else UNMATCHED
	var olds := PackedInt32Array([UNMATCHED, 0, 1 if old_count > 1 else UNMATCHED])
	var best_matches := 0
	var best_cost := INF
	var best_0 := UNMATCHED
	var best_1 := UNMATCHED
	for c0 in 3:
		var m0 := olds[c0]
		if c0 > 0 and m0 == UNMATCHED:
			continue
		var cost0 := 0.0
		if m0 != UNMATCHED:
			cost0 = _movement(0, m0, new_a, new_b, old_a, old_b)
			if cost0 > MATCH_DISTANCE:
				continue
		for c1 in (3 if n1 != UNMATCHED else 1):
			var m1 := olds[c1]
			if c1 > 0 and (m1 == UNMATCHED or m1 == m0):
				continue
			var cost1 := 0.0
			if m1 != UNMATCHED:
				cost1 = _movement(n1, m1, new_a, new_b, old_a, old_b)
				if cost1 > MATCH_DISTANCE:
					continue
			var matches := int(m0 != UNMATCHED) + int(m1 != UNMATCHED)
			var cost := cost0 + cost1
			if matches > best_matches or (matches == best_matches and matches > 0 and cost < best_cost):
				best_matches = matches
				best_cost = cost
				best_0 = m0
				best_1 = m1
	out[0] = best_0
	if n1 != UNMATCHED:
		out[n1] = best_1


## `assign` within each contact pair: a point matches only a point of its own
## pair (at most `POINTS_PER_PAIR` of each), so identity never crosses from
## blade to guard. `new_pair`/`old_pair` name each point's pair.
func assign_pairs(
	new_count: int, new_pair: PackedInt32Array, new_a: PackedFloat64Array, new_b: PackedFloat64Array,
	old_count: int, old_pair: PackedInt32Array, old_a: PackedFloat64Array, old_b: PackedFloat64Array,
	out: PackedInt32Array
) -> void:
	for i in new_count:
		out[i] = UNMATCHED
	for p in PAIRS:
		var fresh := 0
		for i in new_count:
			if new_pair[i] == p and fresh < POINTS_PER_PAIR:
				_pair_new[fresh] = i
				_pair_new_a[fresh] = new_a[i]
				_pair_new_b[fresh] = new_b[i]
				fresh += 1
		var prior := 0
		for i in old_count:
			if old_pair[i] == p and prior < POINTS_PER_PAIR:
				_pair_old[prior] = i
				_pair_old_a[prior] = old_a[i]
				_pair_old_b[prior] = old_b[i]
				prior += 1
		if fresh == 0:
			continue
		assign(fresh, _pair_new_a, _pair_new_b, prior, _pair_old_a, _pair_old_b, _pair_out)
		for k in fresh:
			out[_pair_new[k]] = UNMATCHED if _pair_out[k] == UNMATCHED else _pair_old[_pair_out[k]]


## How far new point `n` moved from old point `o` along the two blades.
static func _movement(n: int, o: int, new_a: PackedFloat64Array, new_b: PackedFloat64Array, old_a: PackedFloat64Array, old_b: PackedFloat64Array) -> float:
	return absf(new_a[n] - old_a[o]) + absf(new_b[n] - old_b[o])


func set_phase(next: Phase) -> void:
	if next == phase:
		return
	phase = next
	phase_ticks = 0


func tick() -> void:
	phase_ticks += 1


## Start of a tick's contact search: last tick's points become the persistence
## reference, and this tick starts with none until the geometry says otherwise.
## The points stay readable after the tick, until the next search begins.
func begin_search() -> void:
	_previous_count = point_count
	for i in point_count:
		_previous_pair[i] = pair[i]
		_previous_a[i] = fraction_a[i]
		_previous_b[i] = fraction_b[i]
		_previous_id[i] = contact_id[i]
		_previous_age[i] = age[i]
		next_contact_id = maxi(next_contact_id, contact_id[i] + 1)
	point_count = 0


## A later substep of the same tick re-records the points from scratch: the
## set describes where the swords ended up touching, and a point that has
## stopped touching must not linger. Persistence still compares with last tick.
func begin_substep() -> void:
	point_count = 0


func is_touching() -> bool:
	return point_count > 0


## Advance the lifecycle from an observed gap. Returns true when this
## observation *begins* a new contact, which is the only moment an impulse is
## resolved.
##
## Only a fully separated pair can begin one: re-touching while still coming
## apart continues the contact it is already in. That rule lives here and
## nowhere else — a second predicate stating it is a second place for it to be
## wrong.
func observe(gap: float, touch: float, separation_epsilon: float) -> bool:
	match phase:
		Phase.SEPARATED:
			if gap <= touch:
				set_phase(Phase.CONTACTING)
				return true
		Phase.CONTACTING:
			if gap > touch:
				set_phase(Phase.SEPARATING)
		Phase.SEPARATING:
			if gap <= touch:
				set_phase(Phase.CONTACTING)
			elif gap > touch + separation_epsilon:
				set_phase(Phase.SEPARATED)
	return false


## Record the touching point at `index` for this tick. A later substep of the
## same tick overwrites an earlier one: the set describes where the swords
## ended up touching, not every place they passed through.
func record_point(index: int, x: float, y: float, a_fraction: float, b_fraction: float, nx: float = 0.0, ny: float = 1.0, point_pair: int = PAIR_BLADES) -> void:
	point_x[index] = x
	point_y[index] = y
	pair[index] = point_pair
	fraction_a[index] = a_fraction
	fraction_b[index] = b_fraction
	point_nx[index] = nx
	point_ny[index] = ny
	normal_impulse[index] = 0.0
	tangent_impulse[index] = 0.0
	point_count = maxi(point_count, index + 1)
	_identify()


## Match this tick's points to last tick's (`assign`) and give each its
## identity: a matched point keeps its contact's id and ages a tick; a new one
## takes the next id. Re-run as each point is recorded, so the final answer is
## the one-to-one assignment over all of them.
func _identify() -> void:
	assign_pairs(point_count, pair, fraction_a, fraction_b, _previous_count, _previous_pair, _previous_a, _previous_b, _match)
	var fresh := next_contact_id
	for i in point_count:
		var prior := _match[i]
		if prior == UNMATCHED:
			persisted[i] = 0
			contact_id[i] = fresh
			age[i] = 0
			fresh += 1
		else:
			persisted[i] = 1
			contact_id[i] = _previous_id[prior]
			age[i] = _previous_age[prior] + 1


func is_persisted(index: int) -> bool:
	return index < point_count and persisted[index] == 1


func set_normal(nx: float, ny: float) -> void:
	normal_x = nx
	normal_y = ny
