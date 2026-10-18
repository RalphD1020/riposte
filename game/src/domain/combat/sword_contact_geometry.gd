class_name SwordContactGeometry
extends RefCounted

## Where two rigid swords touch (CONTACT-MANIFOLD-001, TWO-POINT-001,
## STEEL-TOPOLOGY-001, GUARD-PROTECTION-001). Each sword's steel is two convex
## shapes in the combat plane, placed on the authoritative pose
## (`WeaponKinematics.pose_of`, BLADE-COLLISION-PARITY-001):
##
## ```text
## BLADE  capsule guard_root_apex_radius → tip_radius, blade_radius
## GUARD  the guard root: the crossguard bar (crossguard_radius thick, its two
##        ends ±crossguard_half_span at crossguard_centre_radius) and the two
##        edges from those ends to the apex on the axis, all at the bar's
##        thickness — a rounded triangle, convex, so no blade can wedge in the
##        right angle of bar and blade, standing out at most the bar's own
##        half-depth beyond the drawn sword
## ```
##
## The blade's own steel starts at the guard root's apex, so no stretch of the
## sword is steel twice; a point both shapes would report is the blade's.
##
## Three contact pairs, each one manifold of at most `POINTS_PER_PAIR` (two)
## points, the conventional rule for two convex shapes: blade on blade
## (`PAIR_BLADES`); sword a's blade on sword b's guard (`PAIR_BLADE_ON_GUARD`);
## sword a's guard under sword b's blade (`PAIR_GUARD_ON_BLADE`). Never guard on
## guard. The blade capsule's start cap, within `blade_radius` of the apex,
## sits in the wielder's own guard corner: while that handle or crossguard
## meets the other handle or crossguard, a guard-pair candidate in the cap is
## hilt on hilt and is dropped. A point farther up the blade still meets the
## other guard. A guard pair is steel only on the guard's protected side: the
## attacking blade's centreline must cross the guard's own sword axis beyond
## the bar (`guard_side`), and the side is decided when the pair first touches
## and kept until it parts (`guard_modes`, kept by the caller in
## `SwordContactSet`). From the grip side the guard passes the blade on to
## whatever it meets next — the hands, the handle, the torso — and is never
## hurt geometry itself.
##
## Per pair:
##
## - the closest points are a candidate;
## - two near-parallel segments overlapping lengthwise also contribute the two
##   ends of their overlap — lying along each other they touch along a line,
##   and its ends are what resists them turning against each other;
## - the nearest candidate is the first point; the nearest one that is a
##   different constraint (`_distinct`) is the second. A third distinct touch
##   is counted, never silently absorbed (`dropped_within`).
##
## Points are stored in a canonical, mirror-safe order — by pair, then by
## distance from sword a's origin, then from b's. That order is storage, not
## identity (`SwordContactSet.assign_pairs`).
##
## Gaps are exact in the contact neighbourhood and conservative outside it:
## shapes certainly farther apart than `EXACT_WITHIN` are skipped by the
## broadphase, and `measure` then returns `EXACT_WITHIN` — a lower bound, never
## a distance.
##
## Writes into itself; callers keep one and reuse it.
##
## Implements: /spec/invariants.md#two-point-001
## Implements: /spec/invariants.md#steel-topology-001
## Implements: /spec/invariants.md#guard-protection-001
## Implements: /spec/invariants.md#blade-collision-parity-001
## See also: /docs/concepts/combat.md

const CAPACITY := SwordContactSet.CAPACITY
const POINTS_PER_PAIR := SwordContactSet.POINTS_PER_PAIR
const PAIRS := SwordContactSet.PAIRS
const PAIR_BLADES := SwordContactSet.PAIR_BLADES
const PAIR_BLADE_ON_GUARD := SwordContactSet.PAIR_BLADE_ON_GUARD
const PAIR_GUARD_ON_BLADE := SwordContactSet.PAIR_GUARD_ON_BLADE
## A guard pair's side, decided when it first touches (`SwordContactSet`).
const GUARD_FREE := 0
const GUARD_PROTECTED := 1
const GUARD_PASSING := 2
## Segments closer to parallel than this (|sin| of the angle between them)
## that overlap lengthwise also touch at the two ends of the overlap; and an
## attacking blade this close to parallel with the guard's sword reads its
## side from its nearest point instead of an unstable line crossing.
const PARALLEL_SINE := 0.1
## A second point pushing the same way as the first is a separate constraint
## only when it lies at least this far from it across the contact normal (m).
const MIN_POINT_SEPARATION := 0.04
## Two touches that close together are the same contact only if their normals
## agree this well (cosine, ~30°).
const SAME_NORMAL_COSINE := 0.866
## An interior closest point no nearer than the nearer overlap end, by more
## than this (m), is implied by the ends.
const LINE_TOLERANCE := 1.0e-6
## Beyond the bar's own thickness by this much (m) is clearly one side: a
## numerical tolerance, never a gameplay distance.
const SIDE_TOLERANCE := 1.0e-6
## A guard point and a blade point that are one constraint (same push, same
## place across it) are owned by the blade unless the guard's surface is
## nearer by more than this (m): a numerical tolerance, so a tie at the guard
## root's apex never flips owner from one tick to the next.
const OWNERSHIP_TOLERANCE := 1.0e-9
## The blade segment's start is the apex. A guard-pair point this close to
## that endpoint is the start cap sitting in the wielder's own guard corner,
## not a point up the blade. One millimetre, not `blade_radius`: the forte
## just above the guard still meets the other guard.
const START_CAP := 0.001
## Candidates per pair: per segment pair the closest points and two overlap
## ends; a guard is three segments.
const CANDIDATES_PER_PAIR := 9
const CANDIDATES := PAIRS * CANDIDATES_PER_PAIR
## Gaps are exact out to this far (m).
const EXACT_WITHIN := 0.1

## The manifold: `count` points (0..CAPACITY), each with its pair, closest
## points (on a, on b), surface gap, fraction along each blade (0 at the
## blade's base, 1 at the point; 0 for a guard), and unit normal from b toward
## a. `nearest` is the index of the closest of them.
var count: int = 0
var nearest: int = 0
var point_pair := PackedInt32Array()
var point_ax := PackedFloat64Array()
var point_ay := PackedFloat64Array()
var point_bx := PackedFloat64Array()
var point_by := PackedFloat64Array()
var point_gap := PackedFloat64Array()
var point_fraction_a := PackedFloat64Array()
var point_fraction_b := PackedFloat64Array()
var point_nx := PackedFloat64Array()
var point_ny := PackedFloat64Array()
## Per guard pair (index 0: `PAIR_BLADE_ON_GUARD`, 1: `PAIR_GUARD_ON_BLADE`),
## from the last `measure`: its surface gap whatever its side (INF without a
## crossguard), and the side the attacking blade comes from (`guard_side`:
## +1 protected, −1 the grip side, 0 neither).
var guard_gap := PackedFloat64Array([INF, INF])
var guard_side_reading := PackedInt32Array([0, 0])

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

## This measure's blade steel segments, [x0, y0, x1, y1] from the guard root's
## apex to the point, and guard roots, [Lx, Ly, Rx, Ry, Cx, Cy] (the bar's two
## ends and the apex).
var blade_a := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var blade_b := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var guard_a := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var guard_b := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])

var _contact := SegmentContact.new()
var _fallback := PackedFloat64Array([0.0, 0.0])
var _edge := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## Overlap ends: per end (stride 6) the point on the first segment, on the
## second, their distance and the parameter on the first; then the two
## parameters on the second.
var _line := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
var _c_pair := PackedInt32Array()
var _c_ax := PackedFloat64Array()
var _c_ay := PackedFloat64Array()
var _c_bx := PackedFloat64Array()
var _c_by := PackedFloat64Array()
var _c_gap := PackedFloat64Array()
var _c_nx := PackedFloat64Array()
var _c_ny := PackedFloat64Array()
## Per candidate, the direction of the segment it lies on, on b's side (for a
## degenerate normal).
var _c_ux := PackedFloat64Array()
var _c_uy := PackedFloat64Array()
var _candidates: int = 0
var _spare: int = -1
var _origin_ax: float = 0.0
var _origin_ay: float = 0.0
var _origin_bx: float = 0.0
var _origin_by: float = 0.0
var _uax: float = 0.0
var _uay: float = 0.0
var _ubx: float = 0.0
var _uby: float = 0.0
var _kept := PackedInt32Array()


func _init() -> void:
	_c_pair = _ints(CANDIDATES, PAIR_BLADES)
	_c_ax = _scratch(CANDIDATES, 0.0)
	_c_ay = _scratch(CANDIDATES, 0.0)
	_c_bx = _scratch(CANDIDATES, 0.0)
	_c_by = _scratch(CANDIDATES, 0.0)
	_c_gap = _scratch(CANDIDATES, INF)
	_c_nx = _scratch(CANDIDATES, 0.0)
	_c_ny = _scratch(CANDIDATES, 1.0)
	_c_ux = _scratch(CANDIDATES, 0.0)
	_c_uy = _scratch(CANDIDATES, 1.0)
	_kept = _ints(CAPACITY, -1)
	point_pair = _ints(CAPACITY, PAIR_BLADES)
	point_ax = _scratch(CAPACITY, 0.0)
	point_ay = _scratch(CAPACITY, 0.0)
	point_bx = _scratch(CAPACITY, 0.0)
	point_by = _scratch(CAPACITY, 0.0)
	point_gap = _scratch(CAPACITY, INF)
	point_fraction_a = _scratch(CAPACITY, 0.0)
	point_fraction_b = _scratch(CAPACITY, 0.0)
	point_nx = _scratch(CAPACITY, 0.0)
	point_ny = _scratch(CAPACITY, 1.0)


static func _scratch(size: int, value: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	out.fill(value)
	return out


static func _ints(size: int, value: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(size)
	out.fill(value)
	return out


## Measure two swords posed at origins (`pax`, `pay`) / (`pbx`, `pby`) with
## unit blade directions (`uax`, `uay`) / (`ubx`, `uby`): sword a is
## `weapon_a`, sword b `weapon_b`. (`cax`, `cay`) is sword a's wielder's
## centre, which orients a degenerate normal. `modes` is each guard pair's
## decided side (`GUARD_*`; `PAIR_BLADE_ON_GUARD` then `PAIR_GUARD_ON_BLADE`):
## a free guard pair is steel when its blade is on the protected side, a
## protected one stays steel, a passing one is not. Returns the least surface
## gap over the steel pairs (negative = overlap) — exact up to
## `EXACT_WITHIN`; beyond it, `EXACT_WITHIN` itself as a lower bound.
func measure(cax: float, cay: float, pax: float, pay: float, uax: float, uay: float, pbx: float, pby: float, ubx: float, uby: float, weapon_a: WeaponDefinition, weapon_b: WeaponDefinition, modes: PackedInt32Array = PackedInt32Array([GUARD_FREE, GUARD_FREE])) -> float:
	_candidates = 0
	_spare = -1
	count = 0
	nearest = 0
	_origin_ax = pax
	_origin_ay = pay
	_origin_bx = pbx
	_origin_by = pby
	_uax = uax
	_uay = uay
	_ubx = ubx
	_uby = uby
	_weapon_a = weapon_a
	_weapon_b = weapon_b
	place(pax, pay, uax, uay, weapon_a, blade_a)
	place(pbx, pby, ubx, uby, weapon_b, blade_b)
	var has_guard_a := place_guard(pax, pay, uax, uay, weapon_a, guard_a)
	var has_guard_b := place_guard(pbx, pby, ubx, uby, weapon_b, guard_b)
	_segments(PAIR_BLADES, blade_a, weapon_a.blade_radius, blade_b, weapon_b.blade_radius, ubx, uby)
	guard_gap[0] = INF
	guard_gap[1] = INF
	guard_side_reading[0] = 0
	guard_side_reading[1] = 0
	if has_guard_b:
		guard_side_reading[0] = guard_side(pbx, pby, ubx, uby, weapon_b, blade_a)
		var first := _candidates
		guard_gap[0] = _against_guard(PAIR_BLADE_ON_GUARD, blade_a, weapon_a.blade_radius, guard_b, weapon_b, false)
		if not _steel(modes[0], guard_side_reading[0]):
			_candidates = first
	if has_guard_a:
		guard_side_reading[1] = guard_side(pax, pay, uax, uay, weapon_a, blade_b)
		var first := _candidates
		guard_gap[1] = _against_guard(PAIR_GUARD_ON_BLADE, blade_b, weapon_b.blade_radius, guard_a, weapon_a, true)
		if not _steel(modes[1], guard_side_reading[1]):
			_candidates = first
	## A start cap sitting in the wielder's own guard corner is hilt on hilt
	## once the handles or crossguards meet. It is not a blade meeting a guard.
	_drop_hilt_on_hilt()
	for i in _candidates:
		_candidate_normal(i, cax, cay)
	_select()
	return gap if count > 0 else EXACT_WITHIN


## Whether a guard pair in `mode` is steel this measure, its blade reading
## `side`: a free pair exactly when the blade comes from the protected side; a
## protected one until the blade has gone clearly to the grip side (slipped
## off the quillon — within the bar's band it stays steel, so the line never
## jitters); a passing one never.
static func _steel(mode: int, side: int) -> bool:
	if mode == GUARD_PROTECTED:
		return side != -1
	if mode == GUARD_PASSING:
		return false
	return side == 1



## `weapon`'s blade steel centre segment on a sword at origin (`px`, `py`)
## pointing (`ux`, `uy`), into `out` as [x0, y0, x1, y1]: the guard root's apex
## to the point.
static func place(px: float, py: float, ux: float, uy: float, weapon: WeaponDefinition, out: PackedFloat64Array) -> void:
	var from := weapon.guard_root_apex_radius()
	out[0] = px + ux * from
	out[1] = py + uy * from
	out[2] = px + ux * weapon.tip_radius
	out[3] = py + uy * weapon.tip_radius


## `weapon`'s guard root on a sword at origin (`px`, `py`) pointing (`ux`,
## `uy`), into `out` as [left end, right end, apex] (x, y each). False — and
## nothing written — for a sword with no crossguard.
static func place_guard(px: float, py: float, ux: float, uy: float, weapon: WeaponDefinition, out: PackedFloat64Array) -> bool:
	if weapon.crossguard_half_span <= 0.0:
		return false
	var cx := px + ux * weapon.crossguard_centre_radius
	var cy := py + uy * weapon.crossguard_centre_radius
	var half := weapon.crossguard_half_span
	## perp(û) = (−u_y, u_x): one end each side.
	out[0] = cx - uy * half
	out[1] = cy + ux * half
	out[2] = cx + uy * half
	out[3] = cy - ux * half
	var apex := weapon.guard_root_apex_radius()
	out[4] = px + ux * apex
	out[5] = py + uy * apex
	return true


## Which side of the guard on the sword at (`px`, `py`) pointing (`ux`, `uy`)
## the blade `blade` [x0, y0, x1, y1] comes from (GUARD-PROTECTION-001): +1 the
## protected side, −1 the grip side, 0 within the bar's own thickness — which
## is never protection. It is where the blade's centreline crosses the guard's
## sword axis, as a signed distance along that axis from the bar: beyond the
## bar's thickness toward the point is protected. A blade within
## `PARALLEL_SINE` of parallel to the sword has no stable crossing; it reads
## its point nearest the bar instead.
static func guard_side(px: float, py: float, ux: float, uy: float, weapon: WeaponDefinition, blade: PackedFloat64Array) -> int:
	var gx := px + ux * weapon.crossguard_centre_radius
	var gy := py + uy * weapon.crossguard_centre_radius
	var dx := blade[2] - blade[0]
	var dy := blade[3] - blade[1]
	var length := SimMath.length(dx, dy)
	if length <= SimMath.EPSILON:
		return 0
	var wx := dx / length
	var wy := dy / length
	var sine := ux * wy - uy * wx
	var s := 0.0
	if absf(sine) >= PARALLEL_SINE:
		## The point G + s·û on the blade's line: cross((G + s·û) − B0, ŵ) = 0.
		s = ((blade[0] - gx) * wy - (blade[1] - gy) * wx) / sine
	else:
		var t := SimMath.closest_param_on_segment(blade[0], blade[1], blade[2], blade[3], gx, gy)
		s = (SimMath.mix(blade[0], blade[2], t) - gx) * ux + (SimMath.mix(blade[1], blade[3], t) - gy) * uy
	var limit := weapon.crossguard_radius + SIDE_TOLERANCE
	if s > limit:
		return 1
	if s < -limit:
		return -1
	return 0


## Candidates for `blade` (radius `radius`) against the guard root `guard` of
## `weapon` under `pair`; with `guard_is_a` the guard is sword a's and the
## blade b's. The guard is three segments: the bar, at the crossguard's own
## thickness, and the two edges to the apex at the same thickness; at the
## apex the blade's own, thicker capsule takes over (a point both report is the
## blade's). Returns the pair's least surface gap.
func _against_guard(pair: int, blade: PackedFloat64Array, radius: float, guard: PackedFloat64Array, weapon: WeaponDefinition, guard_is_a: bool) -> float:
	var least := INF
	for edge in 3:
		## The bar (left end → right end), right end → apex, apex → left end.
		var from: int = EDGE_FROM[edge]
		var to: int = EDGE_TO[edge]
		_edge[0] = guard[from]
		_edge[1] = guard[from + 1]
		_edge[2] = guard[to]
		_edge[3] = guard[to + 1]
		var edge_radius := weapon.crossguard_radius
		var found := 0.0
		if guard_is_a:
			found = _segments(pair, _edge, edge_radius, blade, radius, blade[2] - blade[0], blade[3] - blade[1])
		else:
			found = _segments(pair, blade, radius, _edge, edge_radius, _edge[2] - _edge[0], _edge[3] - _edge[1])
		least = minf(least, found)
	return least


## The guard root's edges, as offsets into its [left, right, apex] points.
const EDGE_FROM: PackedInt32Array = [0, 2, 4]
const EDGE_TO: PackedInt32Array = [2, 4, 0]


## Add the candidates of segment `first` (radius `ra`, on sword a's side) and
## `second` (radius `rb`, sword b's) under `pair`; (`ubx`, `uby`) is the b-side
## segment's direction for a degenerate normal. Returns their least surface
## gap (INF when the broadphase skipped them).
func _segments(pair: int, first: PackedFloat64Array, ra: float, second: PackedFloat64Array, rb: float, ubx: float, uby: float) -> float:
	var reach := ra + rb
	var la := SimMath.length(first[2] - first[0], first[3] - first[1])
	var lb := SimMath.length(second[2] - second[0], second[3] - second[1])
	var dx := (first[0] + first[2] - second[0] - second[2]) * 0.5
	var dy := (first[1] + first[3] - second[1] - second[3]) * 0.5
	var limit := (la + lb) * 0.5 + reach + EXACT_WITHIN
	if dx * dx + dy * dy > limit * limit:
		return INF
	var bl := SimMath.length(ubx, uby)
	var bux := ubx / bl if bl > SimMath.EPSILON else 0.0
	var buy := uby / bl if bl > SimMath.EPSILON else 1.0
	SimMath.closest_segments(first[0], first[1], first[2], first[3], second[0], second[1], second[2], second[3], _contact)
	var least := _contact.distance - reach
	var line := _overlap(first, second)
	if not line or not _is_line(_contact.distance):
		_add(pair, _contact.ax, _contact.ay, _contact.bx, _contact.by, _contact.distance - reach, bux, buy)
	if line:
		for end in 2:
			var o := end * 6
			_add(pair, _line[o], _line[o + 1], _line[o + 2], _line[o + 3], _line[o + 4] - reach, bux, buy)
			least = minf(least, _line[o + 4] - reach)
	return least


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


## Two near-parallel segments overlapping lengthwise: write the overlap's two
## ends into `_line` and return true; otherwise false.
func _overlap(first: PackedFloat64Array, second: PackedFloat64Array) -> bool:
	var dax := first[2] - first[0]
	var day := first[3] - first[1]
	var dbx := second[2] - second[0]
	var dby := second[3] - second[1]
	var la := SimMath.length(dax, day)
	var lb := SimMath.length(dbx, dby)
	if la <= SimMath.EPSILON or lb <= SimMath.EPSILON:
		return false
	if absf(dax * dby - day * dbx) > PARALLEL_SINE * la * lb:
		return false
	var s0 := ((second[0] - first[0]) * dax + (second[1] - first[1]) * day) / (la * la)
	var s1 := ((second[2] - first[0]) * dax + (second[3] - first[1]) * day) / (la * la)
	var lo := maxf(0.0, minf(s0, s1))
	var hi := minf(1.0, maxf(s0, s1))
	if (hi - lo) * la < MIN_POINT_SEPARATION:
		return false
	## Each end of the overlap is the endpoint that bounds it, on its own
	## segment, with its closest point on the other — the same physical point
	## whichever sword is a (FRICTION-ORDER-001).
	for end in 2:
		var from_second := (minf(s0, s1) > 0.0) if end == 0 else (maxf(s0, s1) < 1.0)
		var px := 0.0
		var py := 0.0
		var qx := 0.0
		var qy := 0.0
		var s := 0.0
		var t := 0.0
		if from_second:
			var bound := s0 if (s0 < s1) == (end == 0) else s1
			t = 0.0 if bound == s0 else 1.0
			qx = second[0] + dbx * t
			qy = second[1] + dby * t
			s = SimMath.closest_param_on_segment(first[0], first[1], first[2], first[3], qx, qy)
			px = first[0] + dax * s
			py = first[1] + day * s
		else:
			s = 0.0 if end == 0 else 1.0
			px = first[0] + dax * s
			py = first[1] + day * s
			t = SimMath.closest_param_on_segment(second[0], second[1], second[2], second[3], px, py)
			qx = second[0] + dbx * t
			qy = second[1] + dby * t
		var o := end * 6
		_line[o] = px
		_line[o + 1] = py
		_line[o + 2] = qx
		_line[o + 3] = qy
		_line[o + 4] = SimMath.length(px - qx, py - qy)
		_line[o + 5] = s
		_line[12 + end] = t
	return true


## An overlap whose closest points are no nearer than its nearer end is a line
## contact: the ends stand for it.
func _is_line(closest: float) -> bool:
	return minf(_line[4], _line[10]) - closest <= LINE_TOLERANCE


## Drop guard-pair candidates whose blade point is the start cap (within
## `START_CAP` of that blade's apex) when both guards have such a candidate
## and the hilts meet. Blade-on-blade candidates stay. A one-sided guard
## candidate stays. A point farther up the blade still meets the other guard.
func _drop_hilt_on_hilt() -> void:
	if not _hilts_meet() or not _both_hilts_capped():
		return
	var write := 0
	for i in _candidates:
		if _c_pair[i] != PAIR_BLADES and _on_start_cap(i):
			continue
		if write != i:
			_copy_candidate(write, i)
		write += 1
	_candidates = write


## Both guards have a start-cap candidate: each hilt is in the other's
## corner. One blade into one guard is a block and stays.
func _both_hilts_capped() -> bool:
	var on_a := false
	var on_b := false
	for i in _candidates:
		if not _on_start_cap(i):
			continue
		if _c_pair[i] == PAIR_BLADE_ON_GUARD:
			on_a = true
		elif _c_pair[i] == PAIR_GUARD_ON_BLADE:
			on_b = true
	return on_a and on_b


func _on_start_cap(i: int) -> bool:
	var x := _c_bx[i]
	var y := _c_by[i]
	var sx := blade_b[0]
	var sy := blade_b[1]
	if _c_pair[i] == PAIR_BLADE_ON_GUARD:
		x = _c_ax[i]
		y = _c_ay[i]
		sx = blade_a[0]
		sy = blade_a[1]
	return SimMath.length(x - sx, y - sy) <= START_CAP


func _copy_candidate(to: int, from: int) -> void:
	_c_pair[to] = _c_pair[from]
	_c_ax[to] = _c_ax[from]
	_c_ay[to] = _c_ay[from]
	_c_bx[to] = _c_bx[from]
	_c_by[to] = _c_by[from]
	_c_gap[to] = _c_gap[from]
	_c_nx[to] = _c_nx[from]
	_c_ny[to] = _c_ny[from]
	_c_ux[to] = _c_ux[from]
	_c_uy[to] = _c_uy[from]


## True when either handle or crossguard solid meets the other handle or
## crossguard. The bar is the placed guard's first segment. The handle runs
## from the pommel to the bar's underside.
func _hilts_meet() -> bool:
	var least := INF
	var a_bar := _weapon_a.crossguard_half_span > 0.0
	var b_bar := _weapon_b.crossguard_half_span > 0.0
	if a_bar and b_bar:
		least = minf(least, _solid_gap(guard_a[0], guard_a[1], guard_a[2], guard_a[3], guard_b[0], guard_b[1], guard_b[2], guard_b[3], _weapon_a.crossguard_radius, _weapon_b.crossguard_radius))
	var a_hx := _origin_ax
	var a_hy := _origin_ay
	var b_hx := _origin_bx
	var b_hy := _origin_by
	var a_ex := _origin_ax
	var a_ey := _origin_ay
	var b_ex := _origin_bx
	var b_ey := _origin_by
	var along := 0.0
	if a_bar:
		along = maxf(_weapon_a.crossguard_centre_radius - _weapon_a.crossguard_radius, 0.0)
		a_ex = _origin_ax + _uax * along
		a_ey = _origin_ay + _uay * along
	if b_bar:
		along = maxf(_weapon_b.crossguard_centre_radius - _weapon_b.crossguard_radius, 0.0)
		b_ex = _origin_bx + _ubx * along
		b_ey = _origin_by + _uby * along
	least = minf(least, _solid_gap(a_hx, a_hy, a_ex, a_ey, b_hx, b_hy, b_ex, b_ey, _weapon_a.handle_radius, _weapon_b.handle_radius))
	if b_bar:
		least = minf(least, _solid_gap(a_hx, a_hy, a_ex, a_ey, guard_b[0], guard_b[1], guard_b[2], guard_b[3], _weapon_a.handle_radius, _weapon_b.crossguard_radius))
	if a_bar:
		least = minf(least, _solid_gap(guard_a[0], guard_a[1], guard_a[2], guard_a[3], b_hx, b_hy, b_ex, b_ey, _weapon_a.crossguard_radius, _weapon_b.handle_radius))
	return least <= 0.0


func _solid_gap(ax0: float, ay0: float, ax1: float, ay1: float, bx0: float, by0: float, bx1: float, by1: float, ra: float, rb: float) -> float:
	SimMath.closest_segments(ax0, ay0, ax1, ay1, bx0, by0, bx1, by1, _contact)
	return _contact.distance - ra - rb


func _add(pair: int, x0: float, y0: float, x1: float, y1: float, surface_gap: float, ubx: float, uby: float) -> void:
	var i := _candidates
	_c_pair[i] = pair
	_c_ax[i] = x0
	_c_ay[i] = y0
	_c_bx[i] = x1
	_c_by[i] = y1
	_c_gap[i] = surface_gap
	_c_ux[i] = ubx
	_c_uy[i] = uby
	_candidates += 1


## Per pair, the nearest candidate and the nearest one distinct from it. A
## guard point and a kept blade point that are one constraint are one row: the
## blade's (it owns the stretch both shapes reach) unless the guard's surface
## is in front of it, nearer along that same push — then the guard's, and the
## blade point behind it is dropped. Stored in canonical order: by pair, then
## along a, then along b.
func _select() -> void:
	var kept := 0
	for p in PAIRS:
		var first := -1
		for i in _candidates:
			if _c_pair[i] != p or _shadowed(i, kept):
				continue
			if first < 0 or _c_gap[i] < _c_gap[first]:
				first = i
		if first < 0:
			continue
		var second := -1
		for i in _candidates:
			if _c_pair[i] != p or i == first or not _distinct(i, first) or _shadowed(i, kept):
				continue
			if second < 0 or _c_gap[i] < _c_gap[second]:
				second = i
		if second >= 0:
			for i in _candidates:
				if _c_pair[i] == p and i != first and i != second and _distinct(i, first) and _distinct(i, second) and not _shadowed(i, kept) and (_spare < 0 or _c_gap[i] < _c_gap[_spare]):
					_spare = i
		if second >= 0 and _sorts_before(second, first):
			var swap := first
			first = second
			second = swap
		_kept[kept] = first
		kept += 1
		if second >= 0:
			_kept[kept] = second
			kept += 1
	for k in kept:
		if not _occluded(_kept[k], kept):
			_keep(_kept[k])
	if count == 0:
		point_gap[0] = INF


## A guard candidate the blade pair already stands for: one constraint with a
## kept blade point (`_distinct`) whose surface is no farther.
func _shadowed(i: int, kept: int) -> bool:
	if _c_pair[i] == PAIR_BLADES:
		return false
	for k in kept:
		var j := _kept[k]
		if _c_pair[j] == PAIR_BLADES and not _distinct(i, j) and _c_gap[j] <= _c_gap[i] + OWNERSHIP_TOLERANCE:
			return true
	return false


## A kept blade point with a kept guard point in front of it: one constraint,
## the guard's surface nearer along the same push.
func _occluded(j: int, kept: int) -> bool:
	if _c_pair[j] != PAIR_BLADES:
		return false
	for k in kept:
		var i := _kept[k]
		if _c_pair[i] != PAIR_BLADES and not _distinct(i, j) and _c_gap[i] < _c_gap[j] - OWNERSHIP_TOLERANCE:
			return true
	return false


func _keep(i: int) -> void:
	_store(count, i)
	if count == 0 or _c_gap[i] < point_gap[nearest]:
		nearest = count
	count += 1


## Is candidate `i` a different constraint from candidate `kept`?
func _distinct(i: int, kept: int) -> bool:
	if _c_nx[i] * _c_nx[kept] + _c_ny[i] * _c_ny[kept] < SAME_NORMAL_COSINE:
		return true
	var cx := (_c_ax[i] + _c_bx[i] - _c_ax[kept] - _c_bx[kept]) * 0.5
	var cy := (_c_ay[i] + _c_by[i] - _c_ay[kept] - _c_by[kept]) * 0.5
	return absf(cx * -_c_ny[kept] + cy * _c_nx[kept]) >= MIN_POINT_SEPARATION


## Whether the last `measure` found, within `reach`, a third constraint in a
## pair distinct from both points it kept — a real constraint left out
## (`ContactDiagnostics.meaningful_contacts_dropped`).
func dropped_within(reach: float) -> int:
	return 1 if _spare >= 0 and _c_gap[_spare] <= reach else 0


## Canonical order within a pair: by distance from sword a's origin, then
## from sword b's.
func _sorts_before(i: int, j: int) -> bool:
	var di := SimMath.length(_c_ax[i] - _origin_ax, _c_ay[i] - _origin_ay)
	var dj := SimMath.length(_c_ax[j] - _origin_ax, _c_ay[j] - _origin_ay)
	if di != dj:
		return di < dj
	return SimMath.length(_c_bx[i] - _origin_bx, _c_by[i] - _origin_by) < SimMath.length(_c_bx[j] - _origin_bx, _c_by[j] - _origin_by)


func _store(point: int, i: int) -> void:
	var p := _c_pair[i]
	point_pair[point] = p
	point_ax[point] = _c_ax[i]
	point_ay[point] = _c_ay[i]
	point_bx[point] = _c_bx[i]
	point_by[point] = _c_by[i]
	point_gap[point] = _c_gap[i]
	point_fraction_a[point] = 0.0 if p == PAIR_GUARD_ON_BLADE else _fraction(_c_ax[i], _c_ay[i], _origin_ax, _origin_ay, _uax, _uay, _weapon_a)
	point_fraction_b[point] = 0.0 if p == PAIR_BLADE_ON_GUARD else _fraction(_c_bx[i], _c_by[i], _origin_bx, _origin_by, _ubx, _uby, _weapon_b)
	point_nx[point] = _c_nx[i]
	point_ny[point] = _c_ny[i]


var _weapon_a: WeaponDefinition
var _weapon_b: WeaponDefinition


## Where along `weapon`'s blade (0 at its base, 1 at the point) the point
## (`x`, `y`) on the sword at origin (`ox`, `oy`) pointing (`ux`, `uy`) lies.
## The pose's direction is unit only to `SimMath`'s trigonometry (about 1e-9),
## so the projection divides by its squared length: the fraction then names
## exactly the point `BladePose.point_x/y` gives back.
static func _fraction(x: float, y: float, ox: float, oy: float, ux: float, uy: float, weapon: WeaponDefinition) -> float:
	var along := ((x - ox) * ux + (y - oy) * uy) / (ux * ux + uy * uy)
	return SimMath.clamp01((along - weapon.blade_base_radius) / weapon.blade_length())


## Candidate `i`'s unit normal from b toward a. When its closest points
## coincide, the perpendicular of b's segment there, turned toward sword a's
## wielder.
func _candidate_normal(i: int, cax: float, cay: float) -> void:
	var dx := _c_ax[i] - _c_bx[i]
	var dy := _c_ay[i] - _c_by[i]
	var distance := SimMath.length(dx, dy)
	if distance > SimMath.EPSILON:
		_c_nx[i] = dx / distance
		_c_ny[i] = dy / distance
		return
	var px := (_c_ax[i] + _c_bx[i]) * 0.5
	var py := (_c_ay[i] + _c_by[i]) * 0.5
	degenerate_normal(_c_ux[i], _c_uy[i], cax - px, cay - py, _fallback)
	_c_nx[i] = _fallback[0]
	_c_ny[i] = _fallback[1]


## The normal of a contact whose closest points coincide: the perpendicular of
## sword b's segment, perp(û), turned toward (`to_x`, `to_y`), the direction
## from the contact to sword a's wielder. Into `out[0..1]`.
static func degenerate_normal(ubx: float, uby: float, to_x: float, to_y: float, out: PackedFloat64Array) -> void:
	## `0.0 - x`, not `-x`: a zero component stays +0, so a mirrored scene hashes alike.
	var fx := 0.0 - uby
	var fy := ubx
	if fx * to_x + fy * to_y < 0.0:
		fx = 0.0 - fx
		fy = 0.0 - fy
	out[0] = fx
	out[1] = fy
