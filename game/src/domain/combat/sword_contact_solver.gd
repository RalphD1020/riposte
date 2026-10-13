class_name SwordContactSolver
extends RefCounted

## Sequential-impulse solve of one blade-on-blade contact row in weapon
## coordinates (CONTACT-MANIFOLD-001, BLADE-FRICTION-001).
##
## Each side's weapon coordinate responds through its lever (the Jacobian
## projected on the direction, `WeaponKinematics.lever`) and the inertia behind
## it: `Δθ̇ = J·lever / inertia`; and the sword is held, so each wielder's body
## takes the same impulse through its mass: `Δv = J / m`. Along a long lever the
## weapon term dominates and the body barely moves; near the hands, where the
## lever vanishes, the bodies carry it — two crossed hilts stop the fighters
## instead of spinning both swords. The normal stage removes closing velocity with
## restitution and never pulls (`Jn ≥ 0`); the tangent stage then opposes
## sliding within the Coulomb cone (`|Jt| ≤ μ·Jn`). The iteration count is a
## constant — the solver never "works until converged", so a pathological
## frame costs exactly what an ordinary one does.
##
## Restitution is a target set once from the pre-solve closing speed, and each
## iteration removes only what is left of it. The normal is re-solved only after
## a tangent step changed the velocities, so with μ = 0 the solve is exactly the
## one-shot impulse `(1 + e)·closing / K` whatever the iteration count.
##
## Final normal guarantee (RIGID-CONTACT-001): when the fixed iterations end on
## a tangent step, that step changed velocities after the last normal solve and
## may have left a row short of its restitution target. A last normal-only
## top-up then adds non-negative normal impulse until every row meets its
## target — and stops. No tangent step follows it: `|Jt| ≤ μ·Jn` held before
## and a larger `Jn` only widens the cone, and a non-negative projection can
## only remove kinetic energy. Fixed work, no iteration to convergence.
##
## The energy a contact takes out is one law everywhere (IMPACT-PHYSICS-001):
## the drop in `kinetic_energy` across the whole solve, in the solve's own
## masses — restitution, friction, one point or two. For one frictionless row
## that is exactly `½(1 − e²)·v_n² / K`.
##
## Implements: /spec/invariants.md#combat-003
## Implements: /spec/invariants.md#blade-friction-001
## See also: /docs/concepts/combat.md

const ITERATIONS := RigidContactSolver.ITERATIONS
## Frictionless contact: the tangent stage applies nothing.
const FRICTIONLESS := 0.0


## Solve the contact at (`px`, `py`) along the manifold normal between fighters
## `a` and `b`, posed in `pose_a` / `pose_b` (their `vx` / `vy` are used as
## scratch), recording its impulses as point `index` of `manifold`.
##
## `closing` is the pre-solve closing speed along the manifold normal (> 0);
## `cross_a` / `cross_b` each weapon's lever on that normal at the point;
## `inertia_a` / `inertia_b` the effective inertia behind each weapon;
## `inverse_mass_a` / `inverse_mass_b` each wielder's inverse body mass. Writes
## the weapon and body speeds and the point's impulses, and the weapon-speed
## change each side received into `deltas`; returns the accumulated normal
## impulse.
static func solve(
	manifold: SwordContactSet,
	index: int,
	a: FighterState,
	b: FighterState,
	pose_a: BladePose,
	pose_b: BladePose,
	px: float,
	py: float,
	closing: float,
	cross_a: float,
	cross_b: float,
	inertia_a: float,
	inertia_b: float,
	restitution: float,
	friction: float,
	deltas: PackedFloat64Array,
	inverse_mass_a: float = 0.0,
	inverse_mass_b: float = 0.0
) -> float:
	var nx := manifold.normal_x
	var ny := manifold.normal_y
	var bodies := inverse_mass_a + inverse_mass_b
	var normal_mass := cross_a * cross_a / inertia_a + cross_b * cross_b / inertia_b + bodies
	var target := (1.0 + restitution) * closing
	var frictional := friction > 0.0
	var tx := -ny
	var ty := nx
	var tangent_a := 0.0
	var tangent_b := 0.0
	var tangent_mass := 0.0
	if frictional:
		tangent_a = WeaponKinematics.lever(a, pose_a, px, py, tx, ty)
		tangent_b = WeaponKinematics.lever(b, pose_b, px, py, tx, ty)
		tangent_mass = tangent_a * tangent_a / inertia_a + tangent_b * tangent_b / inertia_b + bodies
	var normal_total := 0.0
	var tangent_total := 0.0
	deltas[0] = 0.0
	deltas[1] = 0.0
	var moved := true
	for iteration in ITERATIONS:
		if moved:
			var removed := 0.0
			if iteration > 0:
				removed = closing - closing_speed(a, b, pose_a, pose_b, px, py, nx, ny)
			var normal_step := (target - removed) / normal_mass
			var normal_next := maxf(normal_total + normal_step, 0.0)
			normal_step = normal_next - normal_total
			normal_total = normal_next
			_apply(a, b, normal_step * cross_a / inertia_a, -normal_step * cross_b / inertia_b, deltas)
			_push(a, b, normal_step * nx, normal_step * ny, inverse_mass_a, inverse_mass_b)
		moved = false
		if not frictional or tangent_mass <= SimMath.EPSILON:
			break
		var sliding := -closing_speed(a, b, pose_a, pose_b, px, py, tx, ty)
		var bound := friction * normal_total
		var tangent_next := clampf(tangent_total - sliding / tangent_mass, -bound, bound)
		var tangent_step := tangent_next - tangent_total
		if tangent_step == 0.0:
			break
		tangent_total = tangent_next
		moved = true
		_apply(a, b, tangent_step * tangent_a / inertia_a, -tangent_step * tangent_b / inertia_b, deltas)
		_push(a, b, tangent_step * tx, tangent_step * ty, inverse_mass_a, inverse_mass_b)
	if moved:
		var short := (target - (closing - closing_speed(a, b, pose_a, pose_b, px, py, nx, ny))) / normal_mass
		if short > 0.0:
			normal_total += short
			_apply(a, b, short * cross_a / inertia_a, -short * cross_b / inertia_b, deltas)
			_push(a, b, short * nx, short * ny, inverse_mass_a, inverse_mass_b)
	manifold.normal_impulse[index] = normal_total
	manifold.tangent_impulse[index] = tangent_total
	return normal_total


## Solve a first impact on every touching point of every feature pair at once
## (TWO-POINT-001): a line contact, a blade on the handle and on the other
## blade, or a hilt lock's three constraints are all rows from the first
## instant — never one midpoint impulse that becomes several constraints a
## tick later. The normal rows are one block solved exactly (`ContactLcp`: each
## row's separation at least its restitution target, `Jn ≥ 0`, complementary),
## then a Coulomb tangent on every row at once, at one relaxation
## (FRICTION-ORDER-001), for the same fixed iteration count as one row. One
## mass per coordinate across every row — each side's held sword at its pose
## and its body — so the solve is passive in one kinetic-energy metric and no
## stored point owns it. With one point it is exactly `solve`.
##
## `inertia_*` / `inverse_mass_*` are that one basis; writes every point's
## impulses on the set and each sword's speed change into `deltas`; returns
## the total normal impulse. `closing` receives each row's pre-solve closing
## speed and `separation` its post-solve separating speed (both sized to the
## point count). `lcp` is the caller's block solver (reused, and counting its
## pivot cap).
static func solve_points(
	manifold: SwordContactSet,
	a: FighterState,
	b: FighterState,
	pose_a: BladePose,
	pose_b: BladePose,
	weapon_a: WeaponDefinition,
	weapon_b: WeaponDefinition,
	combat: CombatTuning,
	inertia_a: float,
	inertia_b: float,
	inverse_mass_a: float,
	inverse_mass_b: float,
	deltas: PackedFloat64Array,
	closing: PackedFloat64Array,
	separation: PackedFloat64Array,
	lcp: ContactLcp
) -> float:
	var rows := manifold.point_count
	var bodies := inverse_mass_a + inverse_mass_b
	var lever_a := _zeros(rows)
	var lever_b := _zeros(rows)
	var tangent_a := _zeros(rows)
	var tangent_b := _zeros(rows)
	var tangent_mass := _zeros(rows)
	var mu := _zeros(rows)
	var bias := _zeros(rows)
	var jn := _zeros(rows)
	var jt := _zeros(rows)
	var order := PackedInt32Array()
	order.resize(rows)
	for i in rows:
		order[i] = i
	for i in rows:
		var px := manifold.point_x[i]
		var py := manifold.point_y[i]
		var nx := manifold.point_nx[i]
		var ny := manifold.point_ny[i]
		lever_a[i] = WeaponKinematics.lever(a, pose_a, px, py, nx, ny)
		lever_b[i] = WeaponKinematics.lever(b, pose_b, px, py, nx, ny)
		tangent_a[i] = WeaponKinematics.lever(a, pose_a, px, py, -ny, nx)
		tangent_b[i] = WeaponKinematics.lever(b, pose_b, px, py, -ny, nx)
		tangent_mass[i] = tangent_a[i] * tangent_a[i] / inertia_a + tangent_b[i] * tangent_b[i] / inertia_b + bodies
		mu[i] = ContactMechanics.friction(manifold.feature_a[i], manifold.feature_b[i], combat)
		closing[i] = closing_speed(a, b, pose_a, pose_b, px, py, nx, ny)
		var approach := maxf(closing[i], 0.0)
		bias[i] = ContactMechanics.weapon_restitution(weapon_a, weapon_b, approach) * approach
	var matrix := _zeros(rows * rows)
	for i in rows:
		for j in rows:
			var normals := manifold.point_nx[i] * manifold.point_nx[j] + manifold.point_ny[i] * manifold.point_ny[j]
			matrix[i * rows + j] = lever_a[i] * lever_a[j] / inertia_a + lever_b[i] * lever_b[j] / inertia_b + bodies * normals
		matrix[i * rows + i] *= 1.0 + RigidContactSolver.REGULARIZATION
	deltas[0] = 0.0
	deltas[1] = 0.0
	## Friction rows take one simultaneous step each pass, at one relaxation
	## (FRICTION-ORDER-001): the row stored first gets no more of the friction
	## than the row stored second.
	var friction_rows := PackedInt32Array()
	for i in rows:
		if mu[i] > 0.0 and tangent_mass[i] > SimMath.EPSILON:
			friction_rows.append(i)
	var tangent_coupling := func(fi: int, fj: int) -> float:
		var i := friction_rows[fi]
		var j := friction_rows[fj]
		var normals := manifold.point_nx[i] * manifold.point_nx[j] + manifold.point_ny[i] * manifold.point_ny[j]
		return tangent_a[i] * tangent_a[j] / inertia_a + tangent_b[i] * tangent_b[j] / inertia_b + bodies * normals
	var relax := RigidContactSolver.tangent_relaxation(friction_rows.size(), tangent_coupling)
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
				q[i] = -closing_speed(a, b, pose_a, pose_b, manifold.point_x[i], manifold.point_y[i], manifold.point_nx[i], manifold.point_ny[i]) - bias[i] - shift
			lcp.solve(rows, order, matrix, rows, q, total)
			for i in rows:
				var step := total[i] - jn[i]
				if step != 0.0:
					jn[i] = total[i]
					_row(a, b, step, manifold.point_nx[i], manifold.point_ny[i], lever_a[i], lever_b[i], inertia_a, inertia_b, inverse_mass_a, inverse_mass_b, deltas)
		moved = false
		for i in friction_rows:
			var sliding := -closing_speed(a, b, pose_a, pose_b, manifold.point_x[i], manifold.point_y[i], -manifold.point_ny[i], manifold.point_nx[i])
			var bound := mu[i] * jn[i]
			next_jt[i] = clampf(jt[i] - relax * sliding / tangent_mass[i], -bound, bound)
		for i in friction_rows:
			var step := next_jt[i] - jt[i]
			if step != 0.0:
				jt[i] = next_jt[i]
				moved = true
				_row(a, b, step, -manifold.point_ny[i], manifold.point_nx[i], tangent_a[i], tangent_b[i], inertia_a, inertia_b, inverse_mass_a, inverse_mass_b, deltas)
		if not moved:
			break
	if moved:
		## Final normal guarantee: only added normal impulse (`δ ≥ 0`,
		## `w = A·δ + q ≥ 0`, complementary), no tangent step after it.
		for i in rows:
			q[i] = -closing_speed(a, b, pose_a, pose_b, manifold.point_x[i], manifold.point_y[i], manifold.point_nx[i], manifold.point_ny[i]) - bias[i]
		var top_up := _zeros(rows)
		lcp.solve(rows, order, matrix, rows, q, top_up)
		for i in rows:
			if top_up[i] > 0.0:
				jn[i] += top_up[i]
				_row(a, b, top_up[i], manifold.point_nx[i], manifold.point_ny[i], lever_a[i], lever_b[i], inertia_a, inertia_b, inverse_mass_a, inverse_mass_b, deltas)
	var normal_total := 0.0
	for i in rows:
		manifold.normal_impulse[i] = jn[i]
		manifold.tangent_impulse[i] = jt[i]
		separation[i] = -closing_speed(a, b, pose_a, pose_b, manifold.point_x[i], manifold.point_y[i], manifold.point_nx[i], manifold.point_ny[i])
		normal_total += jn[i]
	return normal_total


static func _zeros(size: int) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	out.fill(0.0)
	return out


## `impulse` along (`dx`, `dy`) at one row: each sword through its lever over
## its inertia, each body through its mass.
static func _row(a: FighterState, b: FighterState, impulse: float, dx: float, dy: float, lever_a: float, lever_b: float, inertia_a: float, inertia_b: float, inverse_mass_a: float, inverse_mass_b: float, deltas: PackedFloat64Array) -> void:
	_apply(a, b, impulse * lever_a / inertia_a, -impulse * lever_b / inertia_b, deltas)
	_push(a, b, impulse * dx, impulse * dy, inverse_mass_a, inverse_mass_b)


## Kinetic energy of the coordinates a sword contact solve moves, in the masses
## it moves them with (J): each held sword's weapon coordinate through its
## effective inertia, each wielder's body through its mass (a zero inverse mass
## is a body the solve does not move). The drop across a solve is the energy
## the contact took out.
static func kinetic_energy(a: FighterState, b: FighterState, inertia_a: float, inertia_b: float, inverse_mass_a: float, inverse_mass_b: float) -> float:
	var energy := 0.5 * (inertia_a * a.weapon.speed * a.weapon.speed + inertia_b * b.weapon.speed * b.weapon.speed)
	if inverse_mass_a > 0.0:
		energy += 0.5 * (a.vx * a.vx + a.vy * a.vy) / inverse_mass_a
	if inverse_mass_b > 0.0:
		energy += 0.5 * (b.vx * b.vx + b.vy * b.vy) / inverse_mass_b
	return energy


## Speed at which the two blades' points at (`px`, `py`) approach each other
## along (`nx`, `ny`), the direction from blade b toward blade a. Negative
## when they move apart; along a tangent it is the (negated) sliding speed.
static func closing_speed(a: FighterState, b: FighterState, pose_a: BladePose, pose_b: BladePose, px: float, py: float, nx: float, ny: float) -> float:
	WeaponKinematics.velocity_into(a, pose_a, px, py)
	WeaponKinematics.velocity_into(b, pose_b, px, py)
	return -((pose_a.vx - pose_b.vx) * nx + (pose_a.vy - pose_b.vy) * ny)


## The impulse (`jx`, `jy`) on blade a, and its reaction on blade b, carried by
## the wielders' bodies.
static func _push(a: FighterState, b: FighterState, jx: float, jy: float, inverse_mass_a: float, inverse_mass_b: float) -> void:
	a.vx += jx * inverse_mass_a
	a.vy += jy * inverse_mass_a
	b.vx -= jx * inverse_mass_b
	b.vy -= jy * inverse_mass_b


static func _apply(a: FighterState, b: FighterState, delta_a: float, delta_b: float, deltas: PackedFloat64Array) -> void:
	a.weapon.speed += delta_a
	b.weapon.speed += delta_b
	deltas[0] += delta_a
	deltas[1] += delta_b
