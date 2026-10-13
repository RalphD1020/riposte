class_name SwordContactSet
extends RefCounted

## The one authoritative record of sword-on-sword contact (COMBAT §43–§45,
## CONTACT-MANIFOLD-001): whether the swords are touching, whether a touch is a
## new contact, and where and how they touch.
##
## A sword is a compound rigid body of three convex features — BLADE, GUARD,
## HILT — so two swords touch through up to nine feature pairs. Each pair is
## its own small manifold of at most `POINTS_PER_PAIR` points, exactly as a
## rigid-body engine gives every shape pair of two compound bodies its own
## manifold: two convex features in the plane never need more than two points,
## but two compound swords can (a hilt lock — the handles along each other
## while each crossguard catches the other's handle — is three). The set keeps
## every one of them; nothing real is dropped to fit a global count
## (TWO-POINT-001).
##
## Two swords that touch are not a sequence of independent strikes. A single
## clash lasts several ticks, and whether the next tick is "still that clash"
## or "a fresh one" is a real question with a real answer: the parts must
## genuinely come apart first. That lifecycle belongs to the sword pair, not to
## a feature pair:
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
## Points are fixed capacity (`CAPACITY`, every pair full) and stored compactly
## in the geometry's canonical order — feature pair (`PAIR_A` / `PAIR_B`), then
## distance from each sword's origin — so nothing here allocates or iterates in
## an order the data does not fix.
##
## A point's index is a storage slot, never its identity (CONTACT-IDENTITY-001).
## Identity is geometric: the same feature pair — blade, guard or hilt on each
## side, never the strong/middle/weak band its fraction falls in — and the
## least movement of the point along both features (`assign`). One matcher
## decides it for everything that asks "is this the same contact as before?":
## the warm-start impulses, `persisted`, a point's `age` and its `contact_id`,
## which presentation keys sparks and scrape loops on. When one end of a line
## contact leaves, the survivor keeps its own history even though its slot
## changes.
##
## There is no bind phase: a bind is a contact that persists, solved every
## tick by `RigidContactSolver` (RIGID-CONTACT-002). The point geometry is a
## reading of this tick; its identity (`contact_id`, `age`) and the hold record
## carry from tick to tick, so they are hashed.
##
## Implements: /spec/invariants.md#combat-002
## Implements: /spec/invariants.md#contact-identity-001
## Implements: /spec/invariants.md#two-point-001
## See also: /docs/concepts/combat.md

enum Phase {
	SEPARATED,
	CONTACTING,
	SEPARATING,
}

## The geometric part of a weapon a contact point lies on.
enum Feature {
	BLADE,
	GUARD,
	HILT,
}

const FEATURES := 3
## Feature pairs in their canonical order: (PAIR_A[i], PAIR_B[i]) —
## blade/blade, blade/guard, guard/blade, guard/guard, blade/hilt, hilt/blade,
## guard/hilt, hilt/guard, hilt/hilt.
const PAIR_A: PackedInt32Array = [0, 0, 1, 1, 0, 2, 1, 2, 2]
const PAIR_B: PackedInt32Array = [0, 1, 0, 1, 2, 0, 2, 1, 2]
## The pair index of (a, b) at `a * FEATURES + b`.
const PAIR_INDEX: PackedInt32Array = [0, 1, 4, 2, 3, 6, 5, 7, 8]
const PAIRS := 9
## Two convex features touch at one point when they cross, at the two ends of
## their overlap when they lie along each other — never more.
const POINTS_PER_PAIR := 2
## Every feature pair at its most.
const CAPACITY := PAIRS * POINTS_PER_PAIR
## The most a point may move along its two features in one tick and still be
## the same contact: the sum of its parameter changes on each feature's centre
## segment (0..1 along the blade, across the crossbar, along the handle), so
## the bound is relative to each feature's own length. Farther is a new point.
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
var feature_a := PackedInt32Array()
var feature_b := PackedInt32Array()
var point_x := PackedFloat64Array()
var point_y := PackedFloat64Array()
## Where along each blade the point lies: 0 at the guard, 1 at the point (a
## guard or hilt contact reads 0).
var fraction_a := PackedFloat64Array()
var fraction_b := PackedFloat64Array()
## Where on each touched feature the point lies: its parameter (0..1) on that
## feature's centre segment (`SwordContactGeometry.local_segment`) — along the
## blade, across the crossbar, along the handle. What presentation needs to put
## a guard or hilt contact on the drawn sword; a reading, never solved on.
var local_a := PackedFloat64Array()
var local_b := PackedFloat64Array()
## Each point's own unit normal, from b toward a. Points of different feature
## pairs need not share a normal (a blade on the handle and on the other blade).
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
## row, with the feature pair and feature coordinates each row was solved at
## (RIGID-CONTACT-003). This is the warm start: the next tick's first velocity
## solve starts a row from the record `assign` matches it to — the same
## physical point, never whichever slot it lands in. Kept compact (slots
## `0..hold_count() − 1`, canonical order). Carried state, so it is hashed. Only
## the velocity stage writes it — never the position stage's pseudo-impulse.
var hold_active := PackedByteArray()
var hold_feature_a := PackedInt32Array()
var hold_feature_b := PackedInt32Array()
var hold_local_a := PackedFloat64Array()
var hold_local_b := PackedFloat64Array()
var hold_normal := PackedFloat64Array()
var hold_tangent := PackedFloat64Array()
## How fast the row still slides after that solve (m/s) — a reading for
## presentation (scrape), never fed back.
var hold_slip := PackedFloat64Array()

## Next `contact_id` to hand out.
var next_contact_id: int = 1

var _previous_count: int = 0
var _previous_a := PackedInt32Array()
var _previous_b := PackedInt32Array()
var _previous_local_a := PackedFloat64Array()
var _previous_local_b := PackedFloat64Array()
var _previous_id := PackedInt32Array()
var _previous_age := PackedInt32Array()
var _match := PackedInt32Array()


func _init() -> void:
	feature_a = _ints(Feature.BLADE)
	feature_b = _ints(Feature.BLADE)
	contact_id = _ints(0)
	age = _ints(0)
	hold_feature_a = _ints(Feature.BLADE)
	hold_feature_b = _ints(Feature.BLADE)
	_previous_a = _ints(Feature.BLADE)
	_previous_b = _ints(Feature.BLADE)
	_previous_id = _ints(0)
	_previous_age = _ints(0)
	_match = _ints(UNMATCHED)
	point_x = _floats(0.0)
	point_y = _floats(0.0)
	fraction_a = _floats(0.0)
	fraction_b = _floats(0.0)
	local_a = _floats(0.0)
	local_b = _floats(0.0)
	point_nx = _floats(0.0)
	point_ny = _floats(1.0)
	normal_impulse = _floats(0.0)
	tangent_impulse = _floats(0.0)
	hold_local_a = _floats(0.0)
	hold_local_b = _floats(0.0)
	hold_normal = _floats(0.0)
	hold_tangent = _floats(0.0)
	hold_slip = _floats(0.0)
	_previous_local_a = _floats(0.0)
	_previous_local_b = _floats(0.0)
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
	for i in CAPACITY:
		contact_id[i] = 0
		age[i] = 0
		persisted[i] = 0
		clear_hold(i)


func clear_hold(index: int) -> void:
	hold_active[index] = 0
	hold_feature_a[index] = Feature.BLADE
	hold_feature_b[index] = Feature.BLADE
	hold_local_a[index] = 0.0
	hold_local_b[index] = 0.0
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


## The canonical index of feature pair (`a`, `b`).
static func pair_of(a: int, b: int) -> int:
	return PAIR_INDEX[a * FEATURES + b]


## The one rule for "the same contact point as before" (CONTACT-IDENTITY-001).
## Each of `new_count` new points (features `new_a`/`new_b`, feature
## coordinates `new_la`/`new_lb`) is matched to at most one of `old_count` old
## points, one to one, into `out` (`UNMATCHED` for a new contact). A pair can
## match only on the same features and within `MATCH_DISTANCE` of movement
## (`|Δlocal_a| + |Δlocal_b|`), so the problem splits by feature pair into at
## most nine independent ones of at most two points each (`_assign_pair`). The
## result never depends on which slot a point happened to occupy. A mirror
## reverses a crossbar's coordinate (s → 1 − s), which leaves every movement,
## and so the assignment, unchanged.
static func assign(
	new_count: int, new_a: PackedInt32Array, new_b: PackedInt32Array, new_la: PackedFloat64Array, new_lb: PackedFloat64Array,
	old_count: int, old_a: PackedInt32Array, old_b: PackedInt32Array, old_la: PackedFloat64Array, old_lb: PackedFloat64Array,
	out: PackedInt32Array
) -> void:
	for i in new_count:
		out[i] = UNMATCHED
	for pair in PAIRS:
		var fa := PAIR_A[pair]
		var fb := PAIR_B[pair]
		var n0 := _nth(new_count, new_a, new_b, fa, fb, 0)
		if n0 == UNMATCHED:
			continue
		var o0 := _nth(old_count, old_a, old_b, fa, fb, 0)
		if o0 == UNMATCHED:
			continue
		var n1 := _nth(new_count, new_a, new_b, fa, fb, 1)
		var o1 := _nth(old_count, old_a, old_b, fa, fb, 1)
		_assign_pair(n0, n1, o0, o1, new_la, new_lb, old_la, old_lb, out)


## The `nth` index (0 or 1) of `count` points on features (`fa`, `fb`), or
## `UNMATCHED`.
static func _nth(count: int, a: PackedInt32Array, b: PackedInt32Array, fa: int, fb: int, nth: int) -> int:
	var seen := 0
	for i in count:
		if a[i] == fa and b[i] == fb:
			if seen == nth:
				return i
			seen += 1
	return UNMATCHED


## One feature pair's matching: new points `n0`, `n1` against old `o0`, `o1`
## (`UNMATCHED` when absent). Of every legal assignment — at most seven — the
## one matching the most points wins, then the least total movement, then the
## first in a fixed order (identity before swap).
static func _assign_pair(
	n0: int, n1: int, o0: int, o1: int,
	new_la: PackedFloat64Array, new_lb: PackedFloat64Array, old_la: PackedFloat64Array, old_lb: PackedFloat64Array,
	out: PackedInt32Array
) -> void:
	var olds := PackedInt32Array([UNMATCHED, o0, o1])
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
			cost0 = _movement(n0, m0, new_la, new_lb, old_la, old_lb)
			if cost0 > MATCH_DISTANCE:
				continue
		for c1 in (3 if n1 != UNMATCHED else 1):
			var m1 := olds[c1]
			if c1 > 0 and (m1 == UNMATCHED or m1 == m0):
				continue
			var cost1 := 0.0
			if m1 != UNMATCHED:
				cost1 = _movement(n1, m1, new_la, new_lb, old_la, old_lb)
				if cost1 > MATCH_DISTANCE:
					continue
			var matches := int(m0 != UNMATCHED) + int(m1 != UNMATCHED)
			var cost := cost0 + cost1
			if matches > best_matches or (matches == best_matches and matches > 0 and cost < best_cost):
				best_matches = matches
				best_cost = cost
				best_0 = m0
				best_1 = m1
	out[n0] = best_0
	if n1 != UNMATCHED:
		out[n1] = best_1


## How far new point `n` moved from old point `o` along their (shared)
## features.
static func _movement(n: int, o: int, new_la: PackedFloat64Array, new_lb: PackedFloat64Array, old_la: PackedFloat64Array, old_lb: PackedFloat64Array) -> float:
	return absf(new_la[n] - old_la[o]) + absf(new_lb[n] - old_lb[o])


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
		_previous_a[i] = feature_a[i]
		_previous_b[i] = feature_b[i]
		_previous_local_a[i] = local_a[i]
		_previous_local_b[i] = local_b[i]
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
func record_point(index: int, a_feature: Feature, b_feature: Feature, x: float, y: float, a_fraction: float, b_fraction: float, nx: float = 0.0, ny: float = 1.0, a_local: float = 0.0, b_local: float = 0.0) -> void:
	feature_a[index] = a_feature
	feature_b[index] = b_feature
	point_x[index] = x
	point_y[index] = y
	fraction_a[index] = a_fraction
	fraction_b[index] = b_fraction
	point_nx[index] = nx
	point_ny[index] = ny
	local_a[index] = a_local
	local_b[index] = b_local
	normal_impulse[index] = 0.0
	tangent_impulse[index] = 0.0
	point_count = maxi(point_count, index + 1)
	_identify()


## Match this tick's points to last tick's (`assign`) and give each its
## identity: a matched point keeps its contact's id and ages a tick; a new one
## takes the next id. Re-run as each point is recorded, so the final answer is
## the one-to-one assignment over all of them.
func _identify() -> void:
	assign(point_count, feature_a, feature_b, local_a, local_b, _previous_count, _previous_a, _previous_b, _previous_local_a, _previous_local_b, _match)
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
