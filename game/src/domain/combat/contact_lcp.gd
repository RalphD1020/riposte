class_name ContactLcp
extends RefCounted

## The exact normal block of a contact solve (RIGID-CONTACT-001, TWO-POINT-001):
## the impulses `λ ≥ 0` with `w = A·λ + q ≥ 0` and `w·λ = 0` over a set of rows.
##
## Every contact row — sword on sword at any feature pair, a sword on a torso,
## the two bodies, a guard stop — moves the same few coordinates (the bodies'
## relative translation and each sword's angle), so `A` is symmetric positive
## semi-definite, and the solvers' diagonal regularization makes it positive
## definite. Then the problem has exactly one solution, and any exact method
## finds the same one. This one is Murty's least-index principal pivoting:
## start with no row pushing; solve the pushing rows exactly; flip the
## lowest-numbered row that breaks a condition (a pushing row with `λ < 0`
## leaves, a resting row still closing joins); repeat. For a positive definite
## block it terminates.
##
## Work follows the rows that actually push, not every subset of the rows (the
## active-set enumeration this replaced cost `2^N`, which is why the whole
## sword pair once had to be held to two points). The pivot count is still
## capped (`MAX_PIVOTS`) so a pathological block costs bounded work; reaching
## the cap is counted (`ContactDiagnostics.pivot_cap_hits`), never absorbed.
##
## Writes into itself; owners keep one and reuse it.
##
## Implements: /spec/invariants.md#rigid-contact-001
## Implements: /spec/invariants.md#two-point-001
## See also: /docs/concepts/combat.md

enum Result {
	## No row needs pushing; every `λ` is zero.
	NOTHING,
	SOLVED,
	## A singular block or the pivot cap; every `λ` is zero.
	FAILED,
}

## Most rows one problem may have.
const MAX_ROWS := 32
## Most principal pivots one solve may take.
const MAX_PIVOTS := 64
## Complementarity slack accepted for a row left out of the pushing set.
const TOLERANCE := 1.0e-9
## A pivot this small relative to its row's diagonal is a singular block.
const SINGULAR := 1.0e-12
## Below this share of its diagonal product a three-row determinant loses too
## much to cancellation (near-duplicate rows, as where a blade, its guard and
## its handle meet); elimination solves it instead.
const CRAMER_SINGULAR := 1.0e-9

## Counts pivot-cap fallbacks when set.
var diagnostics: ContactDiagnostics = null
var _pushing := PackedByteArray()
var _members := PackedInt32Array()
var _work := PackedFloat64Array()
var _rhs := PackedFloat64Array()


func _init() -> void:
	_pushing.resize(MAX_ROWS)
	_members.resize(MAX_ROWS)
	_work.resize(MAX_ROWS * MAX_ROWS)
	_rhs.resize(MAX_ROWS)


## Solve over the `n` rows listed in `rows` (indices into `q`, `lambda` and the
## row-major `matrix` of row length `stride`), in their listed order. Writes
## `lambda` at those rows.
func solve(n: int, rows: PackedInt32Array, matrix: PackedFloat64Array, stride: int, q: PackedFloat64Array, lambda: PackedFloat64Array) -> Result:
	var needed := false
	for k in n:
		lambda[rows[k]] = 0.0
		_pushing[k] = 0
		needed = needed or q[rows[k]] < 0.0
	if not needed:
		return Result.NOTHING
	var count := 0
	for _pivot in MAX_PIVOTS:
		if not _solve_members(count, matrix, stride, q, lambda):
			_clear(n, rows, lambda)
			return Result.FAILED
		var flip := -1
		for k in n:
			var row := rows[k]
			if _pushing[k] == 1:
				if lambda[row] < 0.0:
					flip = k
					break
				continue
			var w := q[row]
			for m in count:
				w += matrix[row * stride + _members[m]] * lambda[_members[m]]
			if w < -TOLERANCE:
				flip = k
				break
		if flip < 0:
			return Result.SOLVED
		_pushing[flip] = 1 - _pushing[flip]
		count = 0
		for k in n:
			lambda[rows[k]] = 0.0
			if _pushing[k] == 1:
				_members[count] = rows[k]
				count += 1
	if diagnostics != null:
		diagnostics.pivot_cap_hits += 1
	_clear(n, rows, lambda)
	return Result.FAILED


func _clear(n: int, rows: PackedInt32Array, lambda: PackedFloat64Array) -> void:
	for k in n:
		lambda[rows[k]] = 0.0


## `A_SS·λ_S = −q_S` over the pushing rows: closed form up to three, fixed
## member-order elimination beyond (positive definite, so no pivoting).
func _solve_members(count: int, matrix: PackedFloat64Array, stride: int, q: PackedFloat64Array, lambda: PackedFloat64Array) -> bool:
	match count:
		0:
			return true
		1:
			var r := _members[0]
			var a := matrix[r * stride + r]
			if a <= SimMath.EPSILON:
				return false
			lambda[r] = -q[r] / a
			return true
		2:
			var i := _members[0]
			var j := _members[1]
			var ii := matrix[i * stride + i]
			var jj := matrix[j * stride + j]
			var ij := matrix[i * stride + j]
			var ji := matrix[j * stride + i]
			var det := ii * jj - ij * ji
			if det <= SINGULAR * ii * jj:
				return false
			lambda[i] = (-q[i] * jj + q[j] * ij) / det
			lambda[j] = (-q[j] * ii + q[i] * ji) / det
			return true
		3:
			if _cramer3(matrix, stride, q, lambda):
				return true
	return _eliminate(count, matrix, stride, q, lambda)


## Three rows by Cramer's rule; false when the block is too close to singular
## for it (elimination then takes over).
func _cramer3(matrix: PackedFloat64Array, stride: int, q: PackedFloat64Array, lambda: PackedFloat64Array) -> bool:
	var r0 := _members[0]
	var r1 := _members[1]
	var r2 := _members[2]
	var m00 := matrix[r0 * stride + r0]
	var m01 := matrix[r0 * stride + r1]
	var m02 := matrix[r0 * stride + r2]
	var m10 := matrix[r1 * stride + r0]
	var m11 := matrix[r1 * stride + r1]
	var m12 := matrix[r1 * stride + r2]
	var m20 := matrix[r2 * stride + r0]
	var m21 := matrix[r2 * stride + r1]
	var m22 := matrix[r2 * stride + r2]
	var det := _det3(m00, m01, m02, m10, m11, m12, m20, m21, m22)
	if det <= CRAMER_SINGULAR * m00 * m11 * m22:
		return false
	var b0 := -q[r0]
	var b1 := -q[r1]
	var b2 := -q[r2]
	lambda[r0] = _det3(b0, m01, m02, b1, m11, m12, b2, m21, m22) / det
	lambda[r1] = _det3(m00, b0, m02, m10, b1, m12, m20, b2, m22) / det
	lambda[r2] = _det3(m00, m01, b0, m10, m11, b1, m20, m21, b2) / det
	return true


static func _det3(a: float, b: float, c: float, d: float, e: float, f: float, g: float, h: float, k: float) -> float:
	return a * (e * k - f * h) - b * (d * k - f * g) + c * (d * h - e * g)


## Fixed member-order Gaussian elimination.
func _eliminate(count: int, matrix: PackedFloat64Array, stride: int, q: PackedFloat64Array, lambda: PackedFloat64Array) -> bool:
	for i in count:
		for j in count:
			_work[i * MAX_ROWS + j] = matrix[_members[i] * stride + _members[j]]
		_rhs[i] = -q[_members[i]]
	for k in count:
		var pivot := _work[k * MAX_ROWS + k]
		if pivot <= SINGULAR * matrix[_members[k] * stride + _members[k]]:
			return false
		for i in range(k + 1, count):
			var factor := _work[i * MAX_ROWS + k] / pivot
			for j in range(k, count):
				_work[i * MAX_ROWS + j] -= factor * _work[k * MAX_ROWS + j]
			_rhs[i] -= factor * _rhs[k]
	for i in range(count - 1, -1, -1):
		var sum := _rhs[i]
		for j in range(i + 1, count):
			sum -= _work[i * MAX_ROWS + j] * lambda[_members[j]]
		lambda[_members[i]] = sum / _work[i * MAX_ROWS + i]
	return true
