class_name StructureContactSolver
extends RefCounted

## A sword's first impact on stage structures (STRUCTURE-CONTACT-001). The
## same law as two swords (`SwordContactSolver.solve_points`,
## CONTACT-MANIFOLD-001) with the second side the world (CONTACT-SIDE-001):
## the structure has zero inverse mass and zero velocity, so each row's
## effective mass is the wielder's alone — `k = c²/M_θ + 1/m` through the
## sword's lever over its held inertia and the wielder's body.
##
## ```text
## normal   exact block (ContactLcp): w = A·Jn + q ≥ 0, Jn ≥ 0, complementary,
##          q = −closing − e·approach  (each row's pair restitution)
## tangent  one simultaneous Coulomb step per pass, |Jt| ≤ μ·Jn, one relaxation
## top-up   a last normal-only solve if the passes ended on a tangent step
## ```
##
## Fixed iteration count, never "until converged". A structure never moves,
## so nothing it does can add energy: the solve only removes kinetic energy
## from the sword and its wielder.
##
## Implements: /spec/invariants.md#structure-contact-001
## See also: /docs/concepts/combat.md

const ITERATIONS := RigidContactSolver.ITERATIONS


## Solve `contact`'s recorded points for `fighter`, posed in `pose`. `pairs`
## holds each row's material pair, `inertia` / `inverse_mass` the sword's held
## inertia and the wielder's inverse body mass. Writes each point's impulses
## on the set, the sword's speed change into `delta[0]`, each row's
## pre-solve closing speed into `closing`; returns the total normal impulse.
static func solve(
	contact: StructureContactSet,
	fighter: FighterState,
	pose: BladePose,
	pairs: Array[ContactPair],
	inertia: float,
	inverse_mass: float,
	delta: PackedFloat64Array,
	closing: PackedFloat64Array,
	lcp: ContactLcp
) -> float:
	var rows := contact.point_count
	var lever := _zeros(rows)
	var tangent := _zeros(rows)
	var tangent_mass := _zeros(rows)
	var bias := _zeros(rows)
	var jn := _zeros(rows)
	var jt := _zeros(rows)
	var order := PackedInt32Array()
	order.resize(rows)
	for i in rows:
		order[i] = i
		var px := contact.point_x[i]
		var py := contact.point_y[i]
		var nx := contact.point_nx[i]
		var ny := contact.point_ny[i]
		lever[i] = WeaponKinematics.lever(fighter, pose, px, py, nx, ny)
		tangent[i] = WeaponKinematics.lever(fighter, pose, px, py, -ny, nx)
		tangent_mass[i] = tangent[i] * tangent[i] / inertia + inverse_mass
		closing[i] = closing_speed(fighter, pose, px, py, nx, ny)
		var approach := maxf(closing[i], 0.0)
		bias[i] = pairs[i].restitution_at(approach) * approach
	var matrix := _zeros(rows * rows)
	for i in rows:
		for j in rows:
			var normals := contact.point_nx[i] * contact.point_nx[j] + contact.point_ny[i] * contact.point_ny[j]
			matrix[i * rows + j] = lever[i] * lever[j] / inertia + inverse_mass * normals
		matrix[i * rows + i] *= 1.0 + RigidContactSolver.REGULARIZATION
	delta[0] = 0.0
	var friction_rows := PackedInt32Array()
	for i in rows:
		if pairs[i].friction > 0.0 and tangent_mass[i] > SimMath.EPSILON:
			friction_rows.append(i)
	var coupling := func(fi: int, fj: int) -> float:
		var i := friction_rows[fi]
		var j := friction_rows[fj]
		var normals := contact.point_nx[i] * contact.point_nx[j] + contact.point_ny[i] * contact.point_ny[j]
		return tangent[i] * tangent[j] / inertia + inverse_mass * normals
	var relax := RigidContactSolver.tangent_relaxation(friction_rows.size(), coupling)
	var next_jt := _zeros(rows)
	var q := _zeros(rows)
	var total := _zeros(rows)
	var moved := true
	for _iteration in ITERATIONS:
		if moved:
			for i in rows:
				var shift := 0.0
				for j in rows:
					shift += matrix[i * rows + j] * jn[j]
				q[i] = -closing_speed(fighter, pose, contact.point_x[i], contact.point_y[i], contact.point_nx[i], contact.point_ny[i]) - bias[i] - shift
			lcp.solve(rows, order, matrix, rows, q, total)
			for i in rows:
				var step := total[i] - jn[i]
				if step != 0.0:
					jn[i] = total[i]
					_apply(fighter, step, contact.point_nx[i], contact.point_ny[i], lever[i], inertia, inverse_mass, delta)
		moved = false
		for i in friction_rows:
			var sliding := -closing_speed(fighter, pose, contact.point_x[i], contact.point_y[i], -contact.point_ny[i], contact.point_nx[i])
			var bound := pairs[i].friction * jn[i]
			next_jt[i] = clampf(jt[i] - relax * sliding / tangent_mass[i], -bound, bound)
		for i in friction_rows:
			var step := next_jt[i] - jt[i]
			if step != 0.0:
				jt[i] = next_jt[i]
				moved = true
				_apply(fighter, step, -contact.point_ny[i], contact.point_nx[i], tangent[i], inertia, inverse_mass, delta)
		if not moved:
			break
	if moved:
		for i in rows:
			q[i] = -closing_speed(fighter, pose, contact.point_x[i], contact.point_y[i], contact.point_nx[i], contact.point_ny[i]) - bias[i]
		var top_up := _zeros(rows)
		lcp.solve(rows, order, matrix, rows, q, top_up)
		for i in rows:
			if top_up[i] > 0.0:
				jn[i] += top_up[i]
				_apply(fighter, top_up[i], contact.point_nx[i], contact.point_ny[i], lever[i], inertia, inverse_mass, delta)
	var normal_total := 0.0
	for i in rows:
		contact.normal_impulse[i] = jn[i]
		contact.tangent_impulse[i] = jt[i]
		normal_total += jn[i]
	return normal_total


## Speed at which the blade point at (`px`, `py`) approaches the structure
## along (`nx`, `ny`), the normal from the structure toward the blade. The
## structure does not move. Negative when the blade moves away; along a
## tangent it is the negated sliding speed.
static func closing_speed(fighter: FighterState, pose: BladePose, px: float, py: float, nx: float, ny: float) -> float:
	WeaponKinematics.velocity_into(fighter, pose, px, py)
	return -(pose.vx * nx + pose.vy * ny)


## Kinetic energy of what the solve moves (J): the sword's coordinate through
## its held inertia and the wielder's body through its mass.
static func kinetic_energy(fighter: FighterState, inertia: float, inverse_mass: float) -> float:
	var energy := 0.5 * inertia * fighter.weapon.speed * fighter.weapon.speed
	if inverse_mass > 0.0:
		energy += 0.5 * (fighter.vx * fighter.vx + fighter.vy * fighter.vy) / inverse_mass
	return energy


static func _apply(fighter: FighterState, impulse: float, dx: float, dy: float, lever: float, inertia: float, inverse_mass: float, delta: PackedFloat64Array) -> void:
	var turn := impulse * lever / inertia
	fighter.weapon.speed += turn
	delta[0] += turn
	fighter.vx += impulse * dx * inverse_mass
	fighter.vy += impulse * dy * inverse_mass


static func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	out.fill(0.0)
	return out
