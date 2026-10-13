class_name SwordContactGeometry
extends RefCounted

## Where two rigid swords touch, feature by feature (CONTACT-MANIFOLD-001,
## GUARD-CONTACT-001, TWO-POINT-001). Each sword is three collidable features
## in the combat plane, all rigid with the blade and all measured from the
## sword model itself:
##
## ```text
## BLADE  capsule from the guard (hilt_radius) to the point, blade_radius
## GUARD  crossbar capsule across the blade at guard_centre_radius,
##        ±guard_half_span either side, guard_radius
## HILT   the handle, pommel to guard centre, handle_radius (the grip's own
##        thickness — the hands around it are presentation, not collision)
## ```
##
## The sweep, the first-impact resolver and the held solver all measure here,
## so a guard or a hilt is the same rigid, frictional contact as a blade —
## never a separate guard physics, and never a cutting edge.
##
## Each feature pair is its own manifold of at most `POINTS_PER_PAIR` (two)
## points — the conventional rule for two convex shapes, applied per shape pair
## of the two compound swords, never to the sword pair as a whole
## (TWO-POINT-001). Per pair:
##
## - its closest points are a candidate;
## - two near-parallel features overlapping lengthwise also contribute the two
##   ends of their overlap — lying along each other they touch along a line,
##   and its ends are what resists them turning against each other. An exactly
##   parallel pair has no single closest point (every point of the overlap is
##   equally close), so there the ends replace it;
## - the nearest candidate is the pair's first point; the nearest one that is a
##   different constraint (`_distinct`: pushing a clearly different way, or
##   spread at least `MIN_POINT_SEPARATION` across the first's normal) is its
##   second. Touches that resist the same motion merge (the same place, or one
##   behind the other along the normal). A third distinct touch within one pair
##   is geometrically impossible for two convex features that are not deeply
##   crossed; it is counted, never silently absorbed (`dropped_within`).
##
## Every pair keeps its own points, so a blade lying on the handle while
## crossing the other blade, a blade caught in the corner of crossbar and
## handle, or a hilt lock with three independent constraints keeps all of
## them. The points are stored compactly in a canonical, mirror-safe order — by
## feature pair, then by distance from sword a's origin, then from b's. That
## order is storage, not identity: which point is "the same contact as last
## tick" is decided geometrically (`SwordContactSet.assign`).
##
## Gaps are exact in the contact neighbourhood and conservative outside it: a
## pair certainly farther apart than `EXACT_WITHIN` is skipped by the
## broadphase, and `measure` then returns `EXACT_WITHIN` — a lower bound, never
## a distance. Callers only ever ask about reaches inside it; nothing may treat
## a result beyond it as an exact separation.
##
## A point's gap may exceed a caller's reach: callers keep the points they
## treat as touching. Nothing here depends on which candidate was found first
## other than through that fixed order, so the result is the same for a scene
## and its mirror image.
##
## Writes into itself; callers keep one and reuse it.
##
## Implements: /spec/invariants.md#guard-contact-001
## Implements: /spec/invariants.md#two-point-001
## See also: /docs/concepts/combat.md

const POINTS_PER_PAIR := SwordContactSet.POINTS_PER_PAIR
const CAPACITY := SwordContactSet.CAPACITY
## Features closer to parallel than this (|sin| of the angle between them)
## that overlap lengthwise also touch at the two ends of the overlap.
const PARALLEL_SINE := 0.1
## A second point pushing the same way as the first is a separate constraint
## only when it lies at least this far from it across the contact normal (m):
## two touches one behind the other along the normal resist the same motion.
const MIN_POINT_SEPARATION := 0.04
## Two touches that close together are the same contact only if their normals
## agree this well (cosine, ~30°). A blade in the corner between a crossbar and
## the handle touches both at once, pushed two different ways: two constraints,
## not one.
const SAME_NORMAL_COSINE := 0.866
## An interior closest point no nearer than the nearer overlap end, by more
## than this (m), is implied by the ends: over an overlap the gap varies
## linearly, so it is least at an end unless the centrelines cross.
const LINE_TOLERANCE := 1.0e-6
## Feature pairs, in the order they are tried (`SwordContactSet.PAIR_A`/`_B`).
const PAIR_A := SwordContactSet.PAIR_A
const PAIR_B := SwordContactSet.PAIR_B
const PAIRS := SwordContactSet.PAIRS
const FEATURES := SwordContactSet.FEATURES
## Candidates: per pair, the closest points and the two ends of an overlap.
const CANDIDATES_PER_PAIR := 3
const CANDIDATES := PAIRS * CANDIDATES_PER_PAIR
## Gaps are exact out to this far (m) — beyond every reach a caller uses (the
## position stage's correction reach, the manifold's separation epsilon). A
## pair whose features are certainly farther apart is not measured: the
## returned gap is then a lower bound, still beyond this, and there are no
## points. Most ticks the swords are far apart and cost almost nothing.
const EXACT_WITHIN := 0.1

## Every pair's points together: `count` points (0..CAPACITY), each with its
## closest points (on a, on b), surface gap, features, fractions along each
## blade (0 at the guard, 1 at the point; a guard or hilt contact reads 0), the
## point's coordinate along each touched feature's own centre segment
## (`local_*`, 0..1 from the start of `local_segment`), and unit normal from b
## toward a. `nearest` is the index of the closest of them.
var count: int = 0
var nearest: int = 0
var point_ax := PackedFloat64Array()
var point_ay := PackedFloat64Array()
var point_bx := PackedFloat64Array()
var point_by := PackedFloat64Array()
var point_gap := PackedFloat64Array()
var point_feature_a := PackedInt32Array()
var point_feature_b := PackedInt32Array()
var point_fraction_a := PackedFloat64Array()
var point_fraction_b := PackedFloat64Array()
var point_local_a := PackedFloat64Array()
var point_local_b := PackedFloat64Array()
var point_nx := PackedFloat64Array()
var point_ny := PackedFloat64Array()

## The nearest point's fields, for callers that need only the first contact.
var ax: float:
	get:
		return point_ax[nearest]
var ay: float:
	get:
		return point_ay[nearest]
var bx: float:
	get:
		return point_bx[nearest]
var by: float:
	get:
		return point_by[nearest]
var gap: float:
	get:
		return point_gap[nearest]
var feature_a: int:
	get:
		return point_feature_a[nearest]
var feature_b: int:
	get:
		return point_feature_b[nearest]
var fraction_a: float:
	get:
		return point_fraction_a[nearest]
var fraction_b: float:
	get:
		return point_fraction_b[nearest]
var nx: float:
	get:
		return point_nx[nearest]
var ny: float:
	get:
		return point_ny[nearest]

var _contact := SegmentContact.new()
var _fallback := PackedFloat64Array([0.0, 0.0])
var _ends_a := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _ends_b := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Overlap ends: per end (stride 6) the point on a, the point on b, their
## distance and the parameter on a; then the two parameters on b.
var _line := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
## Candidate scratch: pair index, points, gap, segment parameters.
var _c_pair := PackedInt32Array()
var _c_ax := PackedFloat64Array()
var _c_ay := PackedFloat64Array()
var _c_bx := PackedFloat64Array()
var _c_by := PackedFloat64Array()
var _c_gap := PackedFloat64Array()
var _c_s := PackedFloat64Array()
var _c_t := PackedFloat64Array()
var _c_nx := PackedFloat64Array()
var _c_ny := PackedFloat64Array()
var _candidates: int = 0
## Per pair, its candidates `_pair_start[p] .. _pair_end[p] − 1`, and the one
## left over that is distinct from both kept points (−1 when none).
var _pair_start := PackedInt32Array()
var _pair_end := PackedInt32Array()
var _spare := PackedInt32Array()
## Per sword (side 0 = a, 1 = b) and feature, cached for that side's weapon
## (`_cache`), at `side × FEATURES + feature`: whether the sword has it, its
## radius, its centre segment in the sword's frame ([along0, across0, along1,
## across1] at slot × 4), its middle along the blade and half its length. The
## two swords are cached separately, so two different weapons meet as
## themselves (COMBATANT-GENERIC-001).
var _weapons: Array[WeaponDefinition] = [null, null]
var _has := PackedByteArray([0, 0, 0, 0, 0, 0])
var _radii := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _frame := PackedFloat64Array([
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
	0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
])
var _mid_along := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _half := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _local := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## This measure's feature middles on each sword ([x, y] at feature × 2).
var _mid_a := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _mid_b := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _origin_ax: float = 0.0
var _origin_ay: float = 0.0
var _origin_bx: float = 0.0
var _origin_by: float = 0.0


func _init() -> void:
	_c_nx.resize(CANDIDATES)
	_c_ny.resize(CANDIDATES)
	_c_pair.resize(CANDIDATES)
	_c_ax.resize(CANDIDATES)
	_c_ay.resize(CANDIDATES)
	_c_bx.resize(CANDIDATES)
	_c_by.resize(CANDIDATES)
	_c_gap.resize(CANDIDATES)
	_c_s.resize(CANDIDATES)
	_c_t.resize(CANDIDATES)
	_pair_start.resize(PAIRS)
	_pair_end.resize(PAIRS)
	_spare.resize(PAIRS)
	_pair_start.fill(0)
	_pair_end.fill(0)
	_spare.fill(-1)
	point_ax = _filled(0.0)
	point_ay = _filled(0.0)
	point_bx = _filled(0.0)
	point_by = _filled(0.0)
	point_gap = _filled(INF)
	point_fraction_a = _filled(0.0)
	point_fraction_b = _filled(0.0)
	point_local_a = _filled(0.0)
	point_local_b = _filled(0.0)
	point_nx = _filled(0.0)
	point_ny = _filled(1.0)
	point_feature_a.resize(CAPACITY)
	point_feature_a.fill(0)
	point_feature_b.resize(CAPACITY)
	point_feature_b.fill(0)


static func _filled(value: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(CAPACITY)
	out.fill(value)
	return out


## Measure two swords posed at pivots (`pax`, `pay`) / (`pbx`, `pby`) with unit
## blade directions (`uax`, `uay`) / (`ubx`, `uby`): sword a is `weapon_a`,
## sword b `weapon_b`. (`cax`, `cay`) is sword a's wielder's centre, which
## orients a degenerate normal. Returns the least surface gap (negative =
## overlap) — exact up to `EXACT_WITHIN`; beyond it, `EXACT_WITHIN` itself as a
## lower bound when the broadphase skipped every pair.
func measure(cax: float, cay: float, pax: float, pay: float, uax: float, uay: float, pbx: float, pby: float, ubx: float, uby: float, weapon_a: WeaponDefinition, weapon_b: WeaponDefinition) -> float:
	_candidates = 0
	_origin_ax = pax
	_origin_ay = pay
	_origin_bx = pbx
	_origin_by = pby
	if weapon_a != _weapons[0]:
		_cache(0, weapon_a)
	if weapon_b != _weapons[1]:
		_cache(1, weapon_b)
	## Each feature's middle on each sword: origin + along·û (the guard's middle
	## is on the blade axis, so `across` is zero there).
	for feature in FEATURES:
		_mid_a[feature * 2] = pax + uax * _mid_along[feature]
		_mid_a[feature * 2 + 1] = pay + uay * _mid_along[feature]
		_mid_b[feature * 2] = pbx + ubx * _mid_along[FEATURES + feature]
		_mid_b[feature * 2 + 1] = pby + uby * _mid_along[FEATURES + feature]
	for index in PAIRS:
		_pair_start[index] = _candidates
		_pair_end[index] = _candidates
		var fa := PAIR_A[index]
		var fb := PAIR_B[index]
		var sb := FEATURES + fb
		if _has[fa] == 0 or _has[sb] == 0:
			continue
		var reach := _radii[fa] + _radii[sb]
		## Every point of a feature lies within half its length of its middle,
		## so a pair whose middles are farther apart than both halves, both
		## radii and `EXACT_WITHIN` has a gap beyond it.
		var dx := _mid_a[fa * 2] - _mid_b[fb * 2]
		var dy := _mid_a[fa * 2 + 1] - _mid_b[fb * 2 + 1]
		var limit := _half[fa] + _half[sb] + reach + EXACT_WITHIN
		if dx * dx + dy * dy > limit * limit:
			continue
		_place(fa, pax, pay, uax, uay, _ends_a)
		_place(sb, pbx, pby, ubx, uby, _ends_b)
		SimMath.closest_segments(_ends_a[0], _ends_a[1], _ends_a[2], _ends_a[3], _ends_b[0], _ends_b[1], _ends_b[2], _ends_b[3], _contact)
		var line := _overlap()
		if not line or not _is_line(_contact.distance):
			_add(index, _contact.ax, _contact.ay, _contact.bx, _contact.by, _contact.distance - reach, _contact.s, _contact.t)
		if line:
			for end in 2:
				var o := end * 6
				_add(index, _line[o], _line[o + 1], _line[o + 2], _line[o + 3], _line[o + 4] - reach, _line[o + 5], _end_t(end))
		_pair_end[index] = _candidates
	for i in _candidates:
		_candidate_normal(i, cax, cay, ubx, uby)
	_select()
	return gap if count > 0 else EXACT_WITHIN


## One side's weapon feature constants, once per weapon: whether it has each
## feature, its radius, its centre segment in the sword's frame, its middle
## along the blade and half its length.
func _cache(side: int, weapon: WeaponDefinition) -> void:
	_weapons[side] = weapon
	for feature in FEATURES:
		var slot := side * FEATURES + feature
		_has[slot] = 1 if has_feature(feature, weapon) else 0
		_radii[slot] = _radius(feature, weapon)
		local_segment(feature, weapon, _local)
		for k in 4:
			_frame[slot * 4 + k] = _local[k]
		_mid_along[slot] = (_local[0] + _local[2]) * 0.5
		_half[slot] = SimMath.length(_local[2] - _local[0], _local[3] - _local[1]) * 0.5


## The centre segment of cached feature `slot` (`side × FEATURES + feature`)
## on a sword at origin (`px`, `py`) pointing (`ux`, `uy`), from the cached
## frame segment (`local_segment`), into `out` as [x0, y0, x1, y1].
func _place(slot: int, px: float, py: float, ux: float, uy: float, out: PackedFloat64Array) -> void:
	var o := slot * 4
	## across is along perp(û) = (−u_y, u_x).
	out[0] = px + ux * _frame[o] - uy * _frame[o + 1]
	out[1] = py + uy * _frame[o] + ux * _frame[o + 1]
	out[2] = px + ux * _frame[o + 2] - uy * _frame[o + 3]
	out[3] = py + uy * _frame[o + 2] + ux * _frame[o + 3]


## The representative location of the touching points (gap ≤ `reach`): their
## centroid, into `out[0..1]` — what an event or an effect is placed at, never
## what is solved. Returns how many points touch.
func centroid(reach: float, out: PackedFloat64Array) -> int:
	var touching := 0
	var sx := 0.0
	var sy := 0.0
	for point in count:
		if point_gap[point] <= reach:
			sx += (point_ax[point] + point_bx[point]) * 0.5
			sy += (point_ay[point] + point_by[point]) * 0.5
			touching += 1
	if touching > 0:
		out[0] = sx / float(touching)
		out[1] = sy / float(touching)
	return touching


## Two near-parallel features overlapping lengthwise: write the overlap's two
## ends into `_line` (per end: a point, b point, distance, parameter on a) and
## return true; otherwise false.
func _overlap() -> bool:
	var dax := _ends_a[2] - _ends_a[0]
	var day := _ends_a[3] - _ends_a[1]
	var dbx := _ends_b[2] - _ends_b[0]
	var dby := _ends_b[3] - _ends_b[1]
	var la := SimMath.length(dax, day)
	var lb := SimMath.length(dbx, dby)
	if la <= SimMath.EPSILON or lb <= SimMath.EPSILON:
		return false
	if absf(dax * dby - day * dbx) > PARALLEL_SINE * la * lb:
		return false
	## b's ends projected on a, as parameters of a; the overlap is where both are.
	var s0 := ((_ends_b[0] - _ends_a[0]) * dax + (_ends_b[1] - _ends_a[1]) * day) / (la * la)
	var s1 := ((_ends_b[2] - _ends_a[0]) * dax + (_ends_b[3] - _ends_a[1]) * day) / (la * la)
	var lo := maxf(0.0, minf(s0, s1))
	var hi := minf(1.0, maxf(s0, s1))
	if (hi - lo) * la < MIN_POINT_SEPARATION:
		return false
	## Each end of the overlap is the endpoint that bounds it, on its own
	## feature, with its closest point on the other — the same physical point
	## whichever sword is a, so the manifold does not depend on slot order
	## (FRICTION-ORDER-001). An end bounded by b's endpoint is that endpoint,
	## never its projection onto a.
	for end in 2:
		var from_b := (minf(s0, s1) > 0.0) if end == 0 else (maxf(s0, s1) < 1.0)
		var px := 0.0
		var py := 0.0
		var qx := 0.0
		var qy := 0.0
		var s := 0.0
		var t := 0.0
		if from_b:
			var bound := s0 if (s0 < s1) == (end == 0) else s1
			t = 0.0 if bound == s0 else 1.0
			qx = _ends_b[0] + dbx * t
			qy = _ends_b[1] + dby * t
			s = SimMath.closest_param_on_segment(_ends_a[0], _ends_a[1], _ends_a[2], _ends_a[3], qx, qy)
			px = _ends_a[0] + dax * s
			py = _ends_a[1] + day * s
		else:
			s = 0.0 if end == 0 else 1.0
			px = _ends_a[0] + dax * s
			py = _ends_a[1] + day * s
			t = SimMath.closest_param_on_segment(_ends_b[0], _ends_b[1], _ends_b[2], _ends_b[3], px, py)
			qx = _ends_b[0] + dbx * t
			qy = _ends_b[1] + dby * t
		var o := end * 6
		_line[o] = px
		_line[o + 1] = py
		_line[o + 2] = qx
		_line[o + 3] = qy
		_line[o + 4] = SimMath.length(px - qx, py - qy)
		_line[o + 5] = s
		_line[12 + end] = t
	return true


func _end_t(end: int) -> float:
	return _line[12 + end]


## An overlap whose closest points are no nearer than its nearer end is a line
## contact: the ends stand for it. (Near-parallel features have no single
## closest point; whichever one the segment test returns lies on the line the
## ends already hold, never a constraint of its own.)
func _is_line(closest: float) -> bool:
	return minf(_line[4], _line[10]) - closest <= LINE_TOLERANCE


func _add(pair: int, x0: float, y0: float, x1: float, y1: float, surface_gap: float, s: float, t: float) -> void:
	var i := _candidates
	_c_pair[i] = pair
	_c_ax[i] = x0
	_c_ay[i] = y0
	_c_bx[i] = x1
	_c_by[i] = y1
	_c_gap[i] = surface_gap
	_c_s[i] = s
	_c_t[i] = t
	_candidates += 1


## Per feature pair, in pair order: its nearest candidate, then the nearest one
## distinct from it, stored in canonical order (along a, then along b). The
## set's `nearest` is the closest point of all.
func _select() -> void:
	count = 0
	nearest = 0
	for pair in PAIRS:
		_spare[pair] = -1
		var start := _pair_start[pair]
		var end := _pair_end[pair]
		var first := -1
		for i in range(start, end):
			if first < 0 or _c_gap[i] < _c_gap[first]:
				first = i
		if first < 0:
			continue
		var second := -1
		for i in range(start, end):
			if i == first or not _distinct(i, first):
				continue
			if second < 0 or _c_gap[i] < _c_gap[second]:
				second = i
		if second >= 0:
			for i in range(start, end):
				if i != first and i != second and _distinct(i, first) and _distinct(i, second):
					_spare[pair] = i
		if second >= 0 and _sorts_before(second, first):
			var swap := first
			first = second
			second = swap
		_keep(first)
		if second >= 0:
			_keep(second)
	if count == 0:
		point_gap[0] = INF


func _keep(i: int) -> void:
	_store(count, i)
	if count == 0 or _c_gap[i] < point_gap[nearest]:
		nearest = count
	count += 1


## Is candidate `i` a different constraint from candidate `kept`? It pushes a
## clearly different way, or it lies at least `MIN_POINT_SEPARATION` across
## `kept`'s normal — two touches one behind the other along it constrain the
## same motion and are one constraint.
func _distinct(i: int, kept: int) -> bool:
	if _c_nx[i] * _c_nx[kept] + _c_ny[i] * _c_ny[kept] < SAME_NORMAL_COSINE:
		return true
	var cx := (_c_ax[i] + _c_bx[i] - _c_ax[kept] - _c_bx[kept]) * 0.5
	var cy := (_c_ay[i] + _c_by[i] - _c_ay[kept] - _c_by[kept]) * 0.5
	return absf(cx * -_c_ny[kept] + cy * _c_nx[kept]) >= MIN_POINT_SEPARATION


## How many feature pairs, in the last `measure`, touch within `reach` in a
## third constraint distinct from both points their manifold kept — a real
## constraint left out (`ContactDiagnostics.meaningful_contacts_dropped`). Two
## convex features touch at no more than two, so this is zero unless two
## features are deeply crossed; it is measured, never assumed.
func dropped_within(reach: float) -> int:
	var dropped := 0
	for pair in PAIRS:
		var spare := _spare[pair]
		if spare >= 0 and _c_gap[spare] <= reach:
			dropped += 1
	return dropped


## Canonical order: by feature pair, then by distance from sword a's origin,
## then from sword b's. Distances, not a feature's own parameter: a crossbar's
## runs from one quillon to the other, which a mirror reverses.
func _sorts_before(i: int, j: int) -> bool:
	if _c_pair[i] != _c_pair[j]:
		return _c_pair[i] < _c_pair[j]
	var di := SimMath.length(_c_ax[i] - _origin_ax, _c_ay[i] - _origin_ay)
	var dj := SimMath.length(_c_ax[j] - _origin_ax, _c_ay[j] - _origin_ay)
	if di != dj:
		return di < dj
	return SimMath.length(_c_bx[i] - _origin_bx, _c_by[i] - _origin_by) < SimMath.length(_c_bx[j] - _origin_bx, _c_by[j] - _origin_by)


func _store(point: int, i: int) -> void:
	var fa := PAIR_A[_c_pair[i]]
	var fb := PAIR_B[_c_pair[i]]
	point_ax[point] = _c_ax[i]
	point_ay[point] = _c_ay[i]
	point_bx[point] = _c_bx[i]
	point_by[point] = _c_by[i]
	point_gap[point] = _c_gap[i]
	point_feature_a[point] = fa
	point_feature_b[point] = fb
	point_local_a[point] = _c_s[i]
	point_local_b[point] = _c_t[i]
	point_fraction_a[point] = _c_s[i] if fa == SwordContactSet.Feature.BLADE else 0.0
	point_fraction_b[point] = _c_t[i] if fb == SwordContactSet.Feature.BLADE else 0.0
	point_nx[point] = _c_nx[i]
	point_ny[point] = _c_ny[i]


## Does this sword carry `feature`? A blade always; a guard or a hilt only
## when it has one.
static func has_feature(feature: int, weapon: WeaponDefinition) -> bool:
	match feature:
		SwordContactSet.Feature.GUARD:
			return weapon.guard_half_span > 0.0
		SwordContactSet.Feature.HILT:
			return weapon.handle_radius > 0.0
	return true


## A feature's centre segment in the sword's own frame — distance along the
## blade from the origin, and across it (+ toward `perp(û)`, the wielder's left
## of the blade) — into `out` as [along0, across0, along1, across1]. The blade
## and the hilt run from the pommel side toward the point; the guard from the
## right quillon to the left. A contact's `local_*` coordinate is its parameter
## on this segment: the solver places it with `_place`, presentation on the
## drawn sword.
static func local_segment(feature: int, weapon: WeaponDefinition, out: PackedFloat64Array) -> void:
	match feature:
		SwordContactSet.Feature.BLADE:
			out[0] = weapon.hilt_radius
			out[1] = 0.0
			out[2] = weapon.tip_radius
			out[3] = 0.0
		SwordContactSet.Feature.GUARD:
			out[0] = weapon.guard_centre_radius
			out[1] = -weapon.guard_half_span
			out[2] = weapon.guard_centre_radius
			out[3] = weapon.guard_half_span
		_:
			out[0] = 0.0
			out[1] = 0.0
			out[2] = weapon.guard_centre_radius
			out[3] = 0.0


static func _radius(feature: int, weapon: WeaponDefinition) -> float:
	match feature:
		SwordContactSet.Feature.BLADE:
			return weapon.blade_radius
		SwordContactSet.Feature.GUARD:
			return weapon.guard_radius
	return weapon.handle_radius


## Candidate `i`'s unit normal from b's feature toward a's. When its closest
## points coincide (the centrelines cross), the perpendicular of b's feature,
## turned toward sword a's wielder.
func _candidate_normal(i: int, cax: float, cay: float, ubx: float, uby: float) -> void:
	var dx := _c_ax[i] - _c_bx[i]
	var dy := _c_ay[i] - _c_by[i]
	var distance := SimMath.length(dx, dy)
	if distance > SimMath.EPSILON:
		_c_nx[i] = dx / distance
		_c_ny[i] = dy / distance
		return
	var px := (_c_ax[i] + _c_bx[i]) * 0.5
	var py := (_c_ay[i] + _c_by[i]) * 0.5
	degenerate_normal(PAIR_B[_c_pair[i]], ubx, uby, cax - px, cay - py, _fallback)
	_c_nx[i] = _fallback[0]
	_c_ny[i] = _fallback[1]


## The normal of a contact whose closest points coincide: the perpendicular of
## sword b's touched feature (the blade and the hilt run along û, so theirs is
## perp(û); the guard runs along perp(û), so its perpendicular is û itself),
## turned toward (`to_x`, `to_y`), the direction from the contact to sword a's
## wielder. Into `out[0..1]`.
static func degenerate_normal(touched: int, ubx: float, uby: float, to_x: float, to_y: float, out: PackedFloat64Array) -> void:
	var across := touched == SwordContactSet.Feature.GUARD
	## `0.0 - x`, not `-x`: a zero component stays +0, so a mirrored scene hashes alike.
	var fx := ubx if across else 0.0 - uby
	var fy := uby if across else ubx
	if fx * to_x + fy * to_y < 0.0:
		fx = 0.0 - fx
		fy = 0.0 - fy
	out[0] = fx
	out[1] = fy
