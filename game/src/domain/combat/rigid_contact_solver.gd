class_name RigidContactSolver
extends RefCounted

## Persistent rigid contact for live combat (RIGID-CONTACT-001, -003).
##
## A first contact is an impulse at its time of impact (`ContactResolver`). A
## contact that persists is a constraint: while a sword rests on a sword or on a
## living fighter's hurt torso, nothing may drive it further in, and sliding
## along it costs Coulomb friction. Every tick the persisted pairs are solved
## twice:
##
## ```text
## velocity  vn >= 0, accumulated Jn >= 0, |accumulated Jt| <= μ·Jn  (no restitution)
## position  overlap beyond contact_slop pushed out, velocities untouched
## ```
##
## The velocity stage is conventional sequential impulse over a fixed
## `ITERATIONS` count: the rows' normal block is solved exactly on the
## accumulated impulse (so a later pass may give normal impulse back, never
## below zero), then each row's tangent in fixed row order, clamped on the
## accumulated tangent impulse to the Coulomb cone and applying only the
## difference. Friction is generic: a fast slide whose demand exceeds `μ·Jn`
## keeps sliding, a slow one inside the cone stops, less pressure means less
## grip, and a contact that is separating has `Jn = 0` and therefore no
## friction at all. μ = 0 is exactly the frictionless solve.
##
## The tick's first solve is warm-started from the last tick's accumulated
## impulses, row by row, only when the row is still the same geometric contact
## (`SwordContactSet.assign`: a contact sliding along the blade keeps its
## identity). The warm start changes where the iterations begin, not the
## problem: the normal block is solved exactly from it.
##
## Two different quantities, kept apart. The velocity stage's impulses are
## physical: they change real velocities, are recorded on the manifold and bound
## friction. The position stage's pseudo-impulse only removes overlap beyond the
## slop: it changes no velocity, is recorded nowhere, is never warm-started, and
## never counts as impact, damage or friction pressure — a slightly deep overlap
## must never turn into a large fake friction bound.
##
## Contact consequences (a swing a hold slows is interrupted) stay in
## `ContactResolver`; this class only reports each sword's `weapon_delta`.
##
## The velocity stage runs before the tick's motion is carried, so the motors'
## drive is what each fighter *tries* to do and the constraint is what the sword
## *can* do; nothing later in the tick overwrites it. The position stage is a
## pseudo-impulse through the same effective mass (`ContactMechanics`): it
## moves θ and the bodies, never their speeds, so correcting overlap adds no
## kinetic energy.
##
## Only persisted pairs are constrained — a blade pair the manifold has seen
## touch, a sword inside a body's entry lifecycle. An overlap that has not been
## resolved as a contact yet is a pending hit and is left to the sweep.
##
## A sword's guard stop is a constraint of the same block, not a clamp the
## solve cannot see. A held sword near its ±guard_limit gets a speculative stop
## row: this tick it may turn toward the stop only as far as the stop allows, so
## the solve never counts on rotation the stop will take away and leave the
## contact to sink (the stop row has no friction and records nothing).
##
## Overlap is corrected with the rows solved together, not one after another.
## A sword pinned between the opponent's blade and the opponent's torso is
## pushed in opposite directions by its two rows; corrected in turn each undoes
## the other and only the opponent's weapon rotation — the one motion that
## separates them — makes progress. So each pass solves the rows' small
## complementarity problem exactly (`w = A·λ + q`, `w ≥ 0`, `λ ≥ 0`, `w·λ = 0`,
## `ContactLcp`). Every touching blade point is a row (`SwordContactSet`, at
## most two): only blade on blade is steel (STEEL-TOPOLOGY-001), so no
## crossguard, handle or hand ever reaches this solve. Fixed iteration and
## pass counts and a fixed pivot cap: the work is bounded and never "until
## converged".
##
## Implements: /spec/invariants.md#rigid-contact-001
## Implements: /spec/invariants.md#rigid-contact-003
## Implements: /spec/invariants.md#blade-friction-001
## See also: /docs/concepts/combat.md

## Fixed sequential-impulse iterations of the velocity stage (normal block,
## then each tangent). Two fighters and a handful of rows converge in far
## fewer; the count is a constant so every tick costs the same.
const ITERATIONS := 4
const POSITION_PASSES := 4
## Most one position pass may turn a sword (rad, ~10 cm at the tip).
const TURN_GUARD := 0.1
## Mid-tick holds — a held contact driven past twice the slop, held at its
## time of impact — one tick may resolve. Past it, the position stage clears
## the rest.
const HOLDS_PER_TICK := 4
## Row order (fixed, and the order everything is solved in):
##
## ```text
## 0 .. 5   ROW_BLADE + k   the steel contact points, two a steel pair, in the
##                          set's canonical order (TWO-POINT-001)
## 6        ROW_BODY        fighter 0's sword on fighter 1's torso
## 7        ROW_BODY + 1    fighter 1's sword on fighter 0's torso
## 8 .. 11  ROW_STRUCTURE   each sword on stage structures, two points a sword
##                          (fighter 0 first), b the WORLD side
## 12       ROW_BODIES      the two push circles
## 13       ROW_STOP        fighter 0's sword against its guard stop
## 14       ROW_STOP + 1    fighter 1's
## ```
##
## The body row joins the *position* stage only: a sword correction resting on
## a torso pushes the bodies, and corrected on its own it would push them into
## each other, so the block keeps every row satisfied at once. It never joins
## the velocity stage — body/body velocity response has exactly one owner,
## `ContactResolver`, with one mass (BODY-CONTACT-OWNERSHIP-001).
const ROW_BLADE := 0
const BLADE_ROWS := SwordContactSet.CAPACITY
const ROW_BODY := ROW_BLADE + BLADE_ROWS
const ROW_STRUCTURE := ROW_BODY + 2
const STRUCTURE_ROWS := 2 * StructureContactSet.CAPACITY
const ROW_BODIES := ROW_STRUCTURE + STRUCTURE_ROWS
const ROW_STOP := ROW_BODIES + 1
const ROWS := ROW_STOP + 2
## A sword this close to its guard stop (rad) brings a stop row into a solve
## it takes part in: more than one tick of the fastest actuated swing.
const STOP_WINDOW := 0.4
## Relative diagonal stiffening, so a pair of exactly opposed rows stays
## solvable (its correction is then bounded by `contact_max_correction`).
const REGULARIZATION := 1.0e-6
## Complementarity slack accepted for a row left out of the pushing set.
const TOLERANCE := ContactLcp.TOLERANCE

## What a row's b side is (CONTACT-SIDE-001): how an impulse along −n there
## reaches the simulation's coordinates. WEAPON is a held sword — its
## wielder's body through the body's mass and the weapon angle through its
## lever over the held inertia. BODY is a body only (a struck torso, the other
## push circle). WORLD does not move: zero inverse mass, no lever, zero
## velocity, so the row's effective mass is side a's alone. Side a of a sword
## row is always a held sword.
enum Side { WEAPON, BODY, WORLD }
## The b index of a WORLD side: no fighter.
const WORLD := -1

## Per row: `a` is the side pushed along +n, `b` the side pushed along −n.
## Blade rows: a = fighter 0, b = fighter 1, both WEAPON. Sword-on-body row:
## a = the sword's wielder, b = the struck body (BODY). Body row: a = fighter
## 0, b = fighter 1, bodies only. Stop row: its own fighter on both sides, the
## sword's angle only (no body term).
var _active := PackedByteArray()
var _a := PackedInt32Array()
var _b := PackedInt32Array()
var _b_side := PackedInt32Array()
## Each sword row's Coulomb coefficient, from its material pair at build.
var _row_mu := PackedFloat64Array()
## Each structure row's feature (CONTACT-IDENTITY-001), for its warm start.
var _row_feature := PackedInt32Array()
var _structure_geometry := StructureContactGeometry.new()
var _nx := PackedFloat64Array()
var _ny := PackedFloat64Array()
var _px := PackedFloat64Array()
var _py := PackedFloat64Array()
var _gap := PackedFloat64Array()
var _lever_a := PackedFloat64Array()
var _lever_b := PackedFloat64Array()
var _inertia_a := PackedFloat64Array()
var _inertia_b := PackedFloat64Array()
var _inverse_mass_a := PackedFloat64Array()
var _inverse_mass_b := PackedFloat64Array()
## The active rows in row order (`_count` of them) — every loop over the
## problem walks these, never the whole capacity.
var _rows := PackedInt32Array()
var _count: int = 0
## The rows' coupling matrix (row-major ROWS × ROWS, written for active pairs
## only), the problem's offset, and its solution.
var _matrix := PackedFloat64Array()
var _q := PackedFloat64Array()
var _lambda := PackedFloat64Array()
## The exact normal block, shared with the first-impact solve so both count
## one pivot cap.
var lcp := ContactLcp.new()
var _poses: Array[BladePose] = [BladePose.new(), BladePose.new()]
var _fighters: Array[FighterState] = [null, null]
var _geometry := SwordContactGeometry.new()
var _held := PackedFloat64Array([0.0, 0.0])
var _sword_inertia := PackedFloat64Array([0.0, 0.0])
var _body_inverse := PackedFloat64Array([0.0, 0.0])
## Which way each stop row's sword would leave its range (+1 toward
## +guard_limit, −1 toward −guard_limit).
var _stop_side := PackedFloat64Array([1.0, 1.0])
## Each fighter's own guard stop (rad), from their weapon.
var _guard_limit := PackedFloat64Array([0.0, 0.0])
## Per blade row (index = point): its fractions along each blade, in the shape
## `SwordContactSet.assign` reads, and the hold record it is the same contact
## as (`UNMATCHED` when new).
var _blade_pair := PackedInt32Array()
var _blade_fraction_a := PackedFloat64Array()
var _blade_fraction_b := PackedFloat64Array()
var _blade_rows: int = 0
var _match := PackedInt32Array()
## Per blade row, the normal impulse the tick's first solve started from (N·s;
## 0 for a new contact) — a reading of which history each row inherited, never
## fed back.
var warm_normal := PackedFloat64Array()
## Scratch for rewriting the hold record compactly.
var _next_normal := PackedFloat64Array()
var _next_tangent := PackedFloat64Array()
var _next_slip := PackedFloat64Array()
## Per row: the levers on the tangent `(−n_y, n_x)`, the tangent's inverse
## effective mass, the row's friction coefficient, and the accumulated normal
## and tangent impulses of this solve.
var _tangent_a := PackedFloat64Array()
var _tangent_b := PackedFloat64Array()
var _tangent_mass := PackedFloat64Array()
var _mu := PackedFloat64Array()
var _jn := PackedFloat64Array()
var _jt := PackedFloat64Array()
## The friction rows of this solve, each pass's steps, and the one relaxation
## every step is taken at (`_build_tangents`).
var _friction_rows := PackedInt32Array()
var _friction_count := 0
var _tangent_step := PackedFloat64Array()
var _tangent_relax := 1.0
## The weapon-speed change each fighter's sword took from the last velocity
## solve (rad/s), for the consequences of being held (`ContactResolver`).
var weapon_delta := PackedFloat64Array([0.0, 0.0])
## Whether each fighter's sword met the opponent (blade or torso)
## with a positive normal impulse in the last velocity solve. Its own guard
## stop is not the opponent and never counts.
var opponent_contact := PackedByteArray([0, 0])
## Cap counters; the owning simulation shares its own instance.
var diagnostics := ContactDiagnostics.new():
	set(value):
		diagnostics = value
		lcp.diagnostics = value


func _init() -> void:
	lcp.diagnostics = diagnostics
	_matrix = _floats(ROWS * ROWS, 0.0)
	_q = _floats(ROWS, 0.0)
	_lambda = _floats(ROWS, 0.0)
	_nx = _floats(ROWS, 0.0)
	_ny = _floats(ROWS, 0.0)
	_px = _floats(ROWS, 0.0)
	_py = _floats(ROWS, 0.0)
	_gap = _floats(ROWS, 0.0)
	_lever_a = _floats(ROWS, 0.0)
	_lever_b = _floats(ROWS, 0.0)
	_inertia_a = _floats(ROWS, 1.0)
	_inertia_b = _floats(ROWS, 1.0)
	_inverse_mass_a = _floats(ROWS, 0.0)
	_inverse_mass_b = _floats(ROWS, 0.0)
	_tangent_a = _floats(ROWS, 0.0)
	_tangent_b = _floats(ROWS, 0.0)
	_tangent_mass = _floats(ROWS, 0.0)
	_mu = _floats(ROWS, 0.0)
	_jn = _floats(ROWS, 0.0)
	_jt = _floats(ROWS, 0.0)
	_friction_rows = _ints(ROWS, 0)
	_tangent_step = _floats(ROWS, 0.0)
	_active.resize(ROWS)
	_active.fill(0)
	_rows = _ints(ROWS, 0)
	## Blade rows and the bodies: fighter 0 is a. Each sword-on-torso row and
	## each stop row belongs to its own fighter.
	_a = _ints(ROWS, 0)
	_b = _ints(ROWS, 1)
	_a[ROW_BODY + 1] = 1
	_b[ROW_BODY + 1] = 0
	_b[ROW_STOP] = 0
	_a[ROW_STOP + 1] = 1
	_b_side = _ints(ROWS, Side.BODY)
	for k in BLADE_ROWS:
		_b_side[ROW_BLADE + k] = Side.WEAPON
	for k in STRUCTURE_ROWS:
		var row := ROW_STRUCTURE + k
		_a[row] = 0 if k < StructureContactSet.CAPACITY else 1
		_b[row] = WORLD
		_b_side[row] = Side.WORLD
	_row_mu = _floats(ROWS, 0.0)
	_row_feature = _ints(ROWS, StructureContactSet.NO_FEATURE)
	_blade_pair = _ints(BLADE_ROWS, SwordContactSet.PAIR_BLADES)
	_blade_fraction_a = _floats(BLADE_ROWS, 0.0)
	_blade_fraction_b = _floats(BLADE_ROWS, 0.0)
	_match = _ints(BLADE_ROWS, SwordContactSet.UNMATCHED)
	warm_normal = _floats(BLADE_ROWS, 0.0)
	_next_normal = _floats(BLADE_ROWS, 0.0)
	_next_tangent = _floats(BLADE_ROWS, 0.0)
	_next_slip = _floats(BLADE_ROWS, 0.0)


static func _floats(size: int, value: float) -> PackedFloat64Array:
	var out := PackedFloat64Array()
	out.resize(size)
	out.fill(value)
	return out


static func _ints(size: int, value: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(size)
	out.fill(value)
	return out


## The effective inertia `slot`'s sword had in the last solve (0 when no
## active row turned it) — the weight of its coordinate in the solve's
## kinetic-energy metric.
func sword_inertia(slot: int) -> float:
	return _sword_inertia[slot]


## The mass `slot`'s body had in the last solve (0 when no active row moved
## it) — its weight in the same metric.
func body_mass(slot: int) -> float:
	return 1.0 / _body_inverse[slot] if _body_inverse[slot] > 0.0 else 0.0


## Remove closing velocity at every persisted contact touching now, and oppose
## sliding there within the Coulomb cone. Returns the total accumulated normal
## impulse (N·s); zero means nothing was closing, and then there is no friction
## either. `warm` marks the tick's first solve, which starts each row from the
## last tick's impulses at the same contact point and records this tick's.
##
## The normal rows are solved together, like the position stage, so opposed
## rows (a sword pinned between a blade and a torso) are stopped through the one
## motion that separates them. Every step is a projection in one kinetic-energy
## metric (`_share_masses`): no clamp is needed to keep anything from being
## flung, because nothing can come out faster than the energy that went in
## allows.
func solve_velocity(state: MatchState, rules: DuelRules, warm: bool = false) -> float:
	weapon_delta[0] = 0.0
	weapon_delta[1] = 0.0
	opponent_contact[0] = 0
	opponent_contact[1] = 0
	if _build(state, rules, 0.0, false) == 0:
		if warm:
			_clear_holds(state)
		return 0.0
	_build_tangents()
	for k in _count:
		_jn[_rows[k]] = 0.0
		_jt[_rows[k]] = 0.0
	_match_holds(state.blade_contact)
	if warm:
		_warm_start(state)
	## A normal solve depends only on velocities, so it is repeated only when
	## a tangent step changed them: with μ = 0 the extra iterations are exactly
	## nothing, not a rounding of the frictionless result.
	var moved := true
	for _iteration in ITERATIONS:
		if moved:
			_solve_normal(state)
		moved = _solve_tangent(state)
	if moved:
		_solve_normal(state)
		if _clamp_tangent(state):
			_push_normal(state)
	_record(state, warm)
	var total := 0.0
	for k in _count:
		var row := _rows[k]
		if _is_sword_row(row):
			total += _jn[row]
			## The world is not the opponent: a sword held on a wall met nothing.
			if _jn[row] > 0.0 and _b_side[row] != Side.WORLD:
				opponent_contact[_a[row]] = 1
				if _b_turns(row):
					opponent_contact[_b[row]] = 1
	return total


## The normal block on the accumulated impulse: solve for the total `Jn ≥ 0`
## that leaves every row non-closing (`w = A·Jn + q′`, `q′ = q − A·Jn_acc`), and
## apply only the difference, which may give impulse back.
func _solve_normal(state: MatchState) -> void:
	for k in _count:
		var row := _rows[k]
		var shift := 0.0
		for m in _count:
			shift += _matrix[row * ROWS + _rows[m]] * _jn[_rows[m]]
		_q[row] = -_closing(state, row) - shift
	## Nothing needing a push releases what was held (every total is zero); a
	## degenerate block keeps it.
	if _solve() == ContactLcp.Result.FAILED:
		return
	for k in _count:
		var row := _rows[k]
		var step := _lambda[row] - _jn[row]
		if step != 0.0:
			_apply_velocity(state, row, step)
			_jn[row] = _lambda[row]


## One simultaneous tangent pass (FRICTION-ORDER-001). Every row's accumulated
## tangent impulse moves toward stopping its slide — all of them read from the
## same velocities, at the solve's one relaxation — and is clamped to
## `±μ·Jn`; only the differences are applied, after every row has chosen.
## Row order therefore decides nothing: the two ends of a line contact share
## its friction whichever is stored first, so swapping the fighters' slots
## swaps nothing physical. One row is exactly the one-row Gauss–Seidel step.
## Returns whether anything moved.
func _solve_tangent(state: MatchState) -> bool:
	for f in _friction_count:
		var row := _friction_rows[f]
		var bound := _mu[row] * _jn[row]
		_tangent_step[f] = clampf(_jt[row] - _tangent_relax * _sliding(state, row) / _tangent_mass[row], -bound, bound)
	var moved := false
	for f in _friction_count:
		var row := _friction_rows[f]
		var next := _tangent_step[f]
		var step := next - _jt[row]
		if step != 0.0:
			_apply_tangent(state, row, step)
			_jt[row] = next
			moved = true
	return moved


## After a final normal solve has given impulse back, hold every tangent to
## its (smaller) cone. Returns whether any tangent was cut back.
func _clamp_tangent(state: MatchState) -> bool:
	var clamped := false
	for k in _count:
		var row := _rows[k]
		if not _has_friction(row):
			continue
		var bound := _mu[row] * _jn[row]
		var next := clampf(_jt[row], -bound, bound)
		var step := next - _jt[row]
		if step != 0.0:
			_apply_tangent(state, row, step)
			_jt[row] = next
			clamped = true
	return clamped


## Cutting a tangent back changed velocities after the last normal solve; any
## row it left closing (a guard stop included) is stopped again by *adding*
## normal impulse only (`δ ≥ 0`, `w = A·δ + q ≥ 0`, complementary). More normal
## impulse only widens every cone, so friction stays within it, and a
## non-negative projection like this one can only remove kinetic energy.
func _push_normal(state: MatchState) -> void:
	for k in _count:
		_q[_rows[k]] = -_closing(state, _rows[k])
	if _solve() != ContactLcp.Result.SOLVED:
		return
	for k in _count:
		var row := _rows[k]
		if _lambda[row] > 0.0:
			_apply_velocity(state, row, _lambda[row])
			_jn[row] += _lambda[row]


func _has_friction(row: int) -> bool:
	return _active[row] == 1 and _is_sword_row(row) and _mu[row] > 0.0 and _tangent_mass[row] > SimMath.EPSILON


## A row where a sword touches something: the blade points and the
## sword-on-torso rows.
static func _is_sword_row(row: int) -> bool:
	return row < ROW_BODIES


## Whether the row's b side has a weapon angle the row turns.
func _b_turns(row: int) -> bool:
	return _b_side[row] == Side.WEAPON


## Whether the row's b side is a body the row moves.
func _b_moves(row: int) -> bool:
	return _b_side[row] != Side.WORLD


static func _is_stop_row(row: int) -> bool:
	return row >= ROW_STOP


## Each sword row's tangent levers, tangent effective mass (in the shared
## metric) and friction coefficient. A sword resting on its stop has left the
## row, along the tangent as well as the normal.
func _build_tangents() -> void:
	for k in _count:
		var row := _rows[k]
		_tangent_a[row] = 0.0
		_tangent_b[row] = 0.0
		_tangent_mass[row] = 0.0
		_mu[row] = 0.0
		if not _is_sword_row(row):
			continue
		var tx := -_ny[row]
		var ty := _nx[row]
		_tangent_a[row] = WeaponKinematics.lever(_fighters[_a[row]], _poses[_a[row]], _px[row], _py[row], tx, ty)
		if _b_turns(row):
			_tangent_b[row] = WeaponKinematics.lever(_fighters[_b[row]], _poses[_b[row]], _px[row], _py[row], tx, ty)
		var turn := _tangent_a[row] * _tangent_a[row] / _inertia_a[row]
		if _b_turns(row):
			turn += _tangent_b[row] * _tangent_b[row] / _inertia_b[row]
		_tangent_mass[row] = _inverse_mass_a[row] + _inverse_mass_b[row] + turn
		_mu[row] = _row_mu[row]
	_friction_count = 0
	for k in _count:
		if _has_friction(_rows[k]):
			_friction_rows[_friction_count] = _rows[k]
			_friction_count += 1
	_tangent_relax = tangent_relaxation(_friction_count, _tangent_coupling)


## The one step size every friction row of a solve is taken at
## (FRICTION-ORDER-001): one over the largest row sum of the normalized
## tangent couplings `|T_ij| / √(T_ii·T_jj)` among the `count` friction rows
## (`coupling(i, j)` over their indices) — a Gershgorin bound on the coupled
## block, so every simultaneous projected step only removes kinetic energy.
## One row, or rows that share nothing, take the full step; the two ends of a
## line contact, which push the same coordinates, take half each.
static func tangent_relaxation(count: int, coupling: Callable) -> float:
	if count <= 1:
		return 1.0
	var widest := 1.0
	for i in count:
		var own := float(coupling.call(i, i))
		if own <= SimMath.EPSILON:
			continue
		var sum := 0.0
		for j in count:
			var other := float(coupling.call(j, j))
			if other > SimMath.EPSILON:
				sum += absf(float(coupling.call(i, j))) / sqrt(own * other)
		widest = maxf(widest, sum)
	return 1.0 / widest


## How much a unit tangent impulse at friction row `j` slides friction row
## `i`: `_coupling` with the tangent levers (the tangents are the normals turned
## a quarter, so their dot is the normals').
func _tangent_coupling(fi: int, fj: int) -> float:
	var i := _friction_rows[fi]
	var j := _friction_rows[fj]
	var sum := 0.0
	for fighter in 2:
		sum += _tangent_turn(i, fighter) * _tangent_turn(j, fighter) * _turn_weight(j, fighter)
		var side_i := _side(i, fighter)
		var side_j := _side(j, fighter)
		if side_i == 0 or side_j == 0:
			continue
		sum += float(side_i * side_j) * (_nx[i] * _nx[j] + _ny[i] * _ny[j]) * _body_weight(j, fighter)
	return sum


func _tangent_turn(row: int, fighter: int) -> float:
	if _a[row] == fighter:
		return _tangent_a[row]
	if _b_turns(row) and _b[row] == fighter:
		return -_tangent_b[row]
	return 0.0


## Which hold record each blade row is the same contact as
## (`SwordContactSet.assign`, CONTACT-IDENTITY-001) — by geometry, never
## by slot.
func _match_holds(manifold: SwordContactSet) -> void:
	manifold.assign_pairs(
		_blade_rows, _blade_pair, _blade_fraction_a, _blade_fraction_b,
		manifold.hold_count(), manifold.hold_pair, manifold.hold_fraction_a, manifold.hold_fraction_b,
		_match
	)


## Start each row from last tick's impulses at the same contact point.
func _warm_start(state: MatchState) -> void:
	var manifold := state.blade_contact
	warm_normal.fill(0.0)
	for point in _blade_rows:
		var prior := _match[point]
		if prior != SwordContactSet.UNMATCHED:
			_warm_row(state, ROW_BLADE + point, manifold.hold_normal[prior], manifold.hold_tangent[prior])
			warm_normal[point] = _jn[ROW_BLADE + point]
	for attacker in 2:
		var lifecycle := state.weapon_body_contacts[attacker]
		if _active[ROW_BODY + attacker] == 1 and lifecycle.hold_active:
			_warm_row(state, ROW_BODY + attacker, lifecycle.hold_normal, lifecycle.hold_tangent)
	## A structure row warm-starts from the same feature only.
	for slot in state.structure_contacts.size():
		var contact := state.structure_contacts[slot]
		for k in StructureContactSet.CAPACITY:
			var row := ROW_STRUCTURE + slot * StructureContactSet.CAPACITY + k
			if _active[row] == 0:
				continue
			var prior := contact.hold_of(_row_feature[row])
			if prior >= 0:
				_warm_row(state, row, contact.hold_normal[prior], contact.hold_tangent[prior])


func _warm_row(state: MatchState, row: int, normal: float, tangent: float) -> void:
	_jn[row] = maxf(normal, 0.0)
	var bound := _mu[row] * _jn[row]
	_jt[row] = clampf(tangent, -bound, bound) if _has_friction(row) else 0.0
	if _jn[row] > 0.0:
		_apply_velocity(state, row, _jn[row])
	if _jt[row] != 0.0:
		_apply_tangent(state, row, _jt[row])


## The tick's impulses per row, for the next tick's warm start, and this
## tick's readings. The first solve of a tick replaces the record; a mid-tick
## re-hold adds to the record of the same contact point (`_match`). The record
## is rewritten compactly in row order, each row carrying the blade fractions
## the next match reads.
func _record(state: MatchState, first: bool) -> void:
	var manifold := state.blade_contact
	var held := manifold.hold_count()
	if _blade_rows > 0:
		for point in _blade_rows:
			var row := ROW_BLADE + point
			var prior := _match[point]
			var carried := not first and prior != SwordContactSet.UNMATCHED
			_next_normal[point] = (manifold.hold_normal[prior] if carried else 0.0) + _jn[row]
			_next_tangent[point] = (manifold.hold_tangent[prior] if carried else 0.0) + _jt[row]
			_next_slip[point] = absf(_sliding(state, row))
			manifold.normal_impulse[point] += _jn[row]
			manifold.tangent_impulse[point] += _jt[row]
		for point in range(_blade_rows, held):
			manifold.clear_hold(point)
		for point in _blade_rows:
			manifold.hold_active[point] = 1
			manifold.hold_pair[point] = _blade_pair[point]
			manifold.hold_fraction_a[point] = _blade_fraction_a[point]
			manifold.hold_fraction_b[point] = _blade_fraction_b[point]
			manifold.hold_normal[point] = _next_normal[point]
			manifold.hold_tangent[point] = _next_tangent[point]
			manifold.hold_slip[point] = _next_slip[point]
	elif first:
		for point in held:
			manifold.clear_hold(point)
	for attacker in 2:
		var row := ROW_BODY + attacker
		var lifecycle := state.weapon_body_contacts[attacker]
		if _active[row] == 1:
			if first or not lifecycle.hold_active:
				lifecycle.hold_normal = 0.0
				lifecycle.hold_tangent = 0.0
			lifecycle.hold_active = true
			lifecycle.hold_normal += _jn[row]
			lifecycle.hold_tangent += _jt[row]
			lifecycle.hold_slip = absf(_sliding(state, row))
			lifecycle.normal_impulse += _jn[row]
			lifecycle.tangent_impulse += _jt[row]
		elif first:
			lifecycle.clear_hold()
	for slot in state.structure_contacts.size():
		_record_structure(state.structure_contacts[slot], slot, first)


## A sword's structure rows into its hold record, keyed by feature. The first
## solve of a tick replaces the record; a mid-tick re-hold of the same feature
## adds to it.
func _record_structure(contact: StructureContactSet, slot: int, first: bool) -> void:
	var count := 0
	var features := PackedInt32Array([StructureContactSet.NO_FEATURE, StructureContactSet.NO_FEATURE])
	var normals := PackedFloat64Array([0.0, 0.0])
	var tangents := PackedFloat64Array([0.0, 0.0])
	for k in StructureContactSet.CAPACITY:
		var row := ROW_STRUCTURE + slot * StructureContactSet.CAPACITY + k
		if _active[row] == 0:
			continue
		var prior := -1 if first else contact.hold_of(_row_feature[row])
		features[count] = _row_feature[row]
		normals[count] = (contact.hold_normal[prior] if prior >= 0 else 0.0) + _jn[row]
		tangents[count] = (contact.hold_tangent[prior] if prior >= 0 else 0.0) + _jt[row]
		count += 1
	if count == 0 and not first:
		return
	contact.clear_holds()
	for i in count:
		contact.hold_feature[i] = features[i]
		contact.hold_normal[i] = normals[i]
		contact.hold_tangent[i] = tangents[i]
	contact.hold_count = count


func _clear_holds(state: MatchState) -> void:
	for point in state.blade_contact.hold_count():
		state.blade_contact.clear_hold(point)
	for lifecycle in state.weapon_body_contacts:
		lifecycle.clear_hold()
	for contact in state.structure_contacts:
		contact.clear_holds()


## Push every persisted contact's overlap back to `contact_slop`, moving
## positions and θ only, in the same mass metric as the velocity stage — the
## cheapest motion that clears the overlap. Each pass re-measures the geometry;
## no contact is corrected by more than `contact_max_correction` in one pass
## (a deep overlap is worked out over passes and ticks), and `TURN_GUARD` bounds
## a degenerate pin. A persisted pair not yet touching but within that reach
## takes part too, held at `w ≥ 0` — so clearing one contact never drives
## another in unseen.
func project(state: MatchState, rules: DuelRules) -> void:
	var combat := rules.combat
	for _pass in POSITION_PASSES:
		if _build(state, rules, combat.contact_max_correction, true) == 0:
			return
		## Swords rest at the slop; bodies never overlap at all, and rest just
		## outside touching like every separated pair (`ArenaConstraints`). A
		## stop row only bounds the others: it never needs pushing itself.
		var needed := false
		for k in _count:
			var row := _rows[k]
			if _is_stop_row(row):
				_q[row] = _gap[row]
				continue
			var slop := -ArenaConstraints.BODY_CONTACT_REST_EPSILON if row == ROW_BODIES else combat.contact_slop
			needed = needed or -_gap[row] > maxf(slop, 0.0) + TOLERANCE
			_q[row] = maxf(_gap[row] + slop, -combat.contact_max_correction)
		if not needed:
			return
		## Overlap with no consistent correction is a degenerate pin: leave it
		## (every hard row stays satisfied) and count the fallback.
		if _solve() != ContactLcp.Result.SOLVED:
			diagnostics.position_guard_hits += 1
			return
		var scale := _turn_guard()
		if scale < 1.0:
			diagnostics.position_guard_hits += 1
		for k in _count:
			var row := _rows[k]
			if _lambda[row] > 0.0:
				_apply_position(state, row, _lambda[row] * scale)


## Find this instant's rows — persisted pairs whose surface gap is at most
## `reach` — and their coupling matrix. The body row takes part only when
## `bodies` (the position stage). Returns the active rows as a bitmask.
func _build(state: MatchState, rules: DuelRules, reach: float, bodies: bool) -> int:
	var mask := 0
	var a := state.fighter(0)
	var b := state.fighter(1)
	_fighters[0] = a
	_fighters[1] = b
	_guard_limit[0] = rules.combatant(0).weapon.guard_limit
	_guard_limit[1] = rules.combatant(1).weapon.guard_limit
	for row in ROWS:
		_active[row] = 0
	WeaponKinematics.pose_of(a, rules.combatant(0), _poses[0])
	WeaponKinematics.pose_of(b, rules.combatant(1), _poses[1])
	_blade_rows = 0
	if a.is_alive() and b.is_alive() and state.blade_contact.phase != SwordContactSet.Phase.SEPARATED:
		_blade_rows = _build_blades(a, b, rules, reach, state.blade_contact.guard_mode)
		for k in _blade_rows:
			_active[ROW_BLADE + k] = 1
			mask |= 1 << (ROW_BLADE + k)
	for attacker in 2:
		var row := ROW_BODY + attacker
		var wielder := state.fighter(attacker)
		var target := state.opponent_of(attacker)
		if not wielder.is_alive() or not target.is_alive() or wielder.is_falling:
			continue
		if not _is_persisted_body(state.weapon_body_contacts[attacker]):
			continue
		if _build_body(row, wielder, target, rules) <= reach:
			_active[row] = 1
			mask |= 1 << row
	for slot in state.structure_contacts.size():
		var wielder := state.fighter(slot)
		if not wielder.is_alive() or wielder.is_falling or not state.structure_contacts[slot].is_persisted():
			continue
		var built := _build_structures(slot, wielder, rules, reach)
		for k in built:
			var row := ROW_STRUCTURE + slot * StructureContactSet.CAPACITY + k
			_active[row] = 1
			mask |= 1 << row
	## The bodies join only a solve the swords already need: on their own they
	## are separated where each remainder is carried (COMBAT-007).
	if bodies and mask != 0 and not a.is_falling and not b.is_falling and _build_bodies(a, b, rules) <= reach:
		_active[ROW_BODIES] = 1
		mask |= 1 << ROW_BODIES
	if mask != 0:
		for fighter in 2:
			if _turns(fighter) and _build_stop(fighter) <= STOP_WINDOW:
				_active[ROW_STOP + fighter] = 1
				mask |= 1 << (ROW_STOP + fighter)
	_count = 0
	for row in ROWS:
		if _active[row] == 1:
			_rows[_count] = row
			_count += 1
	_share_masses()
	for k in _count:
		var i := _rows[k]
		for m in _count:
			var j := _rows[m]
			_matrix[i * ROWS + j] = _coupling(i, j)
		_matrix[i * ROWS + i] *= 1.0 + REGULARIZATION
	return mask


## Does an active sword row turn `fighter`'s sword?
func _turns(fighter: int) -> bool:
	for row in ROWS:
		if _active[row] == 1 and _is_sword_row(row) and _turn(row, fighter) != 0.0:
			return true
	return false


## A stop row for `fighter`'s sword, toward whichever limit it is nearer.
## Returns the angle left before the stop (rad).
func _build_stop(fighter: int) -> float:
	var row := ROW_STOP + fighter
	var angle := _fighters[fighter].weapon.angle
	_stop_side[fighter] = 1.0 if angle >= 0.0 else -1.0
	_gap[row] = _guard_limit[fighter] - absf(angle)
	_lever_a[row] = 0.0
	_lever_b[row] = 0.0
	_inverse_mass_a[row] = 0.0
	_inverse_mass_b[row] = 0.0
	return _gap[row]


## One mass per coordinate across every row, so the solve is a projection in a
## single kinetic-energy metric: passive (it can only remove kinetic energy in
## that metric) and momentum-consistent in it (equal and opposite impulses move
## no momentum). The masses are the contact mechanics' own (IMPACT-PHYSICS-001)
## — each body its real mass, each sword its held inertia — taken, for each
## coordinate, from the first active row that moves it, in row order. A stop
## row adds no coordinate; it weighs its sword with that same inertia.
func _share_masses() -> void:
	for fighter in 2:
		_sword_inertia[fighter] = 0.0
		_body_inverse[fighter] = 0.0
	for row in ROWS:
		if _active[row] == 0 or _is_stop_row(row):
			continue
		if _body_inverse[_a[row]] == 0.0:
			_body_inverse[_a[row]] = _inverse_mass_a[row]
		if _b_moves(row) and _body_inverse[_b[row]] == 0.0:
			_body_inverse[_b[row]] = _inverse_mass_b[row]
		if _is_sword_row(row) and _sword_inertia[_a[row]] == 0.0:
			_sword_inertia[_a[row]] = _inertia_a[row]
		if _b_turns(row) and _sword_inertia[_b[row]] == 0.0:
			_sword_inertia[_b[row]] = _inertia_b[row]
	for row in ROWS:
		if _active[row] == 0:
			continue
		if _is_stop_row(row):
			_inertia_a[row] = _sword_inertia[_a[row]]
			_inertia_b[row] = _inertia_a[row]
			continue
		_inverse_mass_a[row] = _body_inverse[_a[row]]
		_inverse_mass_b[row] = _body_inverse[_b[row]] if _b_moves(row) else 0.0
		## The body row turns no sword (its levers are zero); it keeps its
		## placeholder inertia so the turn terms stay finite.
		if _is_sword_row(row):
			_inertia_a[row] = _sword_inertia[_a[row]]
		if _b_turns(row):
			_inertia_b[row] = _sword_inertia[_b[row]]


static func _is_persisted_body(lifecycle: WeaponBodyContact) -> bool:
	return (
		lifecycle.phase == WeaponBodyContact.Phase.ENTERED
		or lifecycle.phase == WeaponBodyContact.Phase.CONSTRAINING
		or lifecycle.phase == WeaponBodyContact.Phase.EXITING
	)


## The sword rows: every manifold point of the swords' steel
## (`SwordContactGeometry`: blade on blade, and each guard pair at the side its
## contact decided, `guard_modes`) whose surface gap is at most `reach`, in
## the geometry's canonical order — the same points the sweep records — with
## both swords' inertia there. Returns how many rows were built
## (0..`BLADE_ROWS`).
func _build_blades(a: FighterState, b: FighterState, rules: DuelRules, reach: float, guard_modes: PackedInt32Array) -> int:
	var pose_a := _poses[0]
	var pose_b := _poses[1]
	_geometry.measure(a.x, a.y, pose_a.origin_x, pose_a.origin_y, pose_a.ux, pose_a.uy, pose_b.origin_x, pose_b.origin_y, pose_b.ux, pose_b.uy, rules.combatant(0).weapon, rules.combatant(1).weapon, guard_modes)
	var built := 0
	for point in _geometry.count:
		if _geometry.point_gap[point] > reach:
			continue
		var row := ROW_BLADE + built
		var nx := _geometry.point_nx[point]
		var ny := _geometry.point_ny[point]
		var px := (_geometry.point_ax[point] + _geometry.point_bx[point]) * 0.5
		var py := (_geometry.point_ay[point] + _geometry.point_by[point]) * 0.5
		_gap[row] = _geometry.point_gap[point]
		_set_point(row, px, py, nx, ny)
		_blade_pair[built] = _geometry.point_pair[point]
		_blade_fraction_a[built] = _geometry.point_fraction_a[point]
		_blade_fraction_b[built] = _geometry.point_fraction_b[point]
		_lever_a[row] = WeaponKinematics.lever(a, pose_a, px, py, nx, ny)
		_lever_b[row] = WeaponKinematics.lever(b, pose_b, px, py, nx, ny)
		ContactMechanics.held_sword(a, pose_a, px, py, rules.combatant(0), _held)
		_inertia_a[row] = _held[0]
		_inverse_mass_a[row] = _held[1]
		ContactMechanics.held_sword(b, pose_b, px, py, rules.combatant(1), _held)
		_inertia_b[row] = _held[0]
		_inverse_mass_b[row] = _held[1]
		_row_mu[row] = rules.blade_pair().friction
		built += 1
	return built


## A body row's geometry and the wielder's sword inertia: `wielder`'s sword
## against `target`'s hurt torso. Returns its surface gap.
func _build_body(row: int, wielder: FighterState, target: FighterState, rules: DuelRules) -> float:
	var wielding := rules.spec_of(wielder)
	var struck := rules.spec_of(target)
	var weapon := wielding.weapon
	var pose := _poses[wielder.slot]
	var hx := pose.point_x(weapon.blade_base_radius)
	var hy := pose.point_y(weapon.blade_base_radius)
	var tx := pose.point_x(weapon.tip_radius)
	var ty := pose.point_y(weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, target.x, target.y)
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	## From the torso toward the blade: the wielder's side is pushed along +n.
	var nx := px - target.x
	var ny := py - target.y
	var distance := SimMath.length(nx, ny)
	if distance > SimMath.EPSILON:
		nx /= distance
		ny /= distance
	else:
		nx = wielder.x - target.x
		ny = wielder.y - target.y
		var apart := SimMath.length(nx, ny)
		nx = nx / apart if apart > SimMath.EPSILON else 1.0
		ny = ny / apart if apart > SimMath.EPSILON else 0.0
	_set_point(row, px, py, nx, ny)
	_lever_a[row] = WeaponKinematics.lever(wielder, pose, px, py, nx, ny)
	_lever_b[row] = 0.0
	_inertia_a[row] = ContactMechanics.weapon_inertia(pose, wielding)
	_inverse_mass_a[row] = ContactMechanics.body_inverse_mass(wielding)
	_inertia_b[row] = 1.0
	_inverse_mass_b[row] = ContactMechanics.body_inverse_mass(struck)
	_row_mu[row] = rules.sword_body_pair(wielder.slot).friction
	_gap[row] = distance - struck.fighter.hurt_radius - weapon.blade_radius
	return _gap[row]


## Fighter `slot`'s sword against the structures, at most two rows (its
## deepest features within `reach`), each a held sword against the WORLD side.
## Returns how many were built.
func _build_structures(slot: int, wielder: FighterState, rules: DuelRules, reach: float) -> int:
	var spec := rules.combatant(slot)
	var weapon := spec.weapon
	var pose := _poses[slot]
	_structure_geometry.measure(pose.point_x(weapon.blade_base_radius), pose.point_y(weapon.blade_base_radius), pose.point_x(weapon.tip_radius), pose.point_y(weapon.tip_radius), weapon.blade_radius, rules.structures, reach)
	for k in _structure_geometry.count:
		var row := ROW_STRUCTURE + slot * StructureContactSet.CAPACITY + k
		var px := _structure_geometry.point_x[k]
		var py := _structure_geometry.point_y[k]
		var nx := _structure_geometry.normal_x[k]
		var ny := _structure_geometry.normal_y[k]
		_set_point(row, px, py, nx, ny)
		_gap[row] = _structure_geometry.gap[k]
		_lever_a[row] = WeaponKinematics.lever(wielder, pose, px, py, nx, ny)
		_lever_b[row] = 0.0
		ContactMechanics.held_sword(wielder, pose, px, py, spec, _held)
		_inertia_a[row] = _held[0]
		_inverse_mass_a[row] = _held[1]
		_inertia_b[row] = 1.0
		_inverse_mass_b[row] = 0.0
		_row_mu[row] = rules.structure_pair(slot, _structure_geometry.structure[k]).friction
		_row_feature[row] = StructureContactSet.feature_of(_structure_geometry.structure[k], _structure_geometry.shape[k])
	return _structure_geometry.count


## The body row: the two push circles, fighter 0 pushed along +n (from fighter
## 1 toward fighter 0). Bodies only — no lever on either sword. Each body
## brings its real mass, as in every other contact. Returns the gap.
func _build_bodies(a: FighterState, b: FighterState, rules: DuelRules) -> float:
	var nx := a.x - b.x
	var ny := a.y - b.y
	var distance := SimMath.length(nx, ny)
	if distance > SimMath.EPSILON:
		nx /= distance
		ny /= distance
	else:
		nx = 1.0
		ny = 0.0
	_set_point(ROW_BODIES, (a.x + b.x) * 0.5, (a.y + b.y) * 0.5, nx, ny)
	_lever_a[ROW_BODIES] = 0.0
	_lever_b[ROW_BODIES] = 0.0
	_inertia_a[ROW_BODIES] = 1.0
	_inertia_b[ROW_BODIES] = 1.0
	_inverse_mass_a[ROW_BODIES] = ContactMechanics.body_inverse_mass(rules.spec_of(a))
	_inverse_mass_b[ROW_BODIES] = ContactMechanics.body_inverse_mass(rules.spec_of(b))
	_gap[ROW_BODIES] = distance - (rules.spec_of(a).fighter.push_radius + rules.spec_of(b).fighter.push_radius)
	return _gap[ROW_BODIES]


func _set_point(row: int, px: float, py: float, nx: float, ny: float) -> void:
	_px[row] = px
	_py[row] = py
	_nx[row] = nx
	_ny[row] = ny


## How much a unit push at row `j` separates row `i`, through the coordinates
## they share (each fighter's body along both normals, each weapon angle through
## both levers), with the shared masses of `_share_masses` — the same ones the
## corrections apply, so the matrix is symmetric and the solve predicts exactly
## what it does. On the diagonal it is the row's inverse effective mass.
func _coupling(i: int, j: int) -> float:
	var sum := 0.0
	for fighter in 2:
		sum += _turn(i, fighter) * _turn(j, fighter) * _turn_weight(j, fighter)
		if _is_stop_row(i) or _is_stop_row(j):
			continue
		var side_i := _side(i, fighter)
		var side_j := _side(j, fighter)
		if side_i == 0 or side_j == 0:
			continue
		sum += float(side_i * side_j) * (_nx[i] * _nx[j] + _ny[i] * _ny[j]) * _body_weight(j, fighter)
	return sum


## +1 when `fighter` is row `row`'s a side, −1 its b side, 0 not in it.
func _side(row: int, fighter: int) -> int:
	if _a[row] == fighter:
		return 1
	if _b[row] == fighter:
		return -1
	return 0


func _body_weight(row: int, fighter: int) -> float:
	return _inverse_mass_a[row] if _a[row] == fighter else _inverse_mass_b[row]


## The row's signed lever on `fighter`'s weapon angle (0 when the row does not
## turn that weapon). A stop row pushes its sword back from the stop: −1 per
## unit impulse toward the limit it guards.
func _turn(row: int, fighter: int) -> float:
	if _is_stop_row(row):
		return -_stop_side[fighter] if _a[row] == fighter else 0.0
	if _a[row] == fighter:
		return _lever_a[row]
	if _b_turns(row) and _b[row] == fighter:
		return -_lever_b[row]
	return 0.0


func _turn_weight(row: int, fighter: int) -> float:
	if _is_stop_row(row):
		return 1.0 / _sword_inertia[fighter] if _sword_inertia[fighter] > 0.0 else 0.0
	return 1.0 / (_inertia_a[row] if _a[row] == fighter else _inertia_b[row])


## Solve `w = A·λ + q` (`w ≥ 0`, `λ ≥ 0`, `w·λ = 0`) over the active rows
## exactly (`ContactLcp`). Writes `_lambda` at every active row.
func _solve() -> ContactLcp.Result:
	return lcp.solve(_count, _rows, _matrix, ROWS, _q, _lambda)


## Uniform scale (≤ 1) that keeps one position pass from turning either sword
## more than `TURN_GUARD`. Each contact's own correction is already bounded by
## `contact_max_correction`; this only catches a degenerate pin (two exactly
## opposed rows) whose solve would spin a sword to fix a few millimetres.
## Healthy play never reaches it.
func _turn_guard() -> float:
	var largest := 0.0
	for fighter in 2:
		var turn := 0.0
		for k in _count:
			var row := _rows[k]
			if _lambda[row] > 0.0:
				turn += _lambda[row] * _turn(row, fighter) * _turn_weight(row, fighter)
		largest = maxf(largest, absf(turn))
	return TURN_GUARD / largest if largest > TURN_GUARD else 1.0


## Closing speed at a row (> 0 approaching). A stop row "closes" at the sword's
## speed toward its stop beyond what reaches the stop by the end of the tick:
## the speculative bound `θ̇·side ≤ (limit − |θ|) / dt`.
func _closing(state: MatchState, row: int) -> float:
	if _is_stop_row(row):
		var fighter := row - ROW_STOP
		return _stop_side[fighter] * _fighters[fighter].weapon.speed - _gap[row] / SimulationTimebase.TICK_SECONDS
	return -_relative(state, row, _nx[row], _ny[row])


## How fast side a slides past side b at a sword row's point along its tangent
## `(−n_y, n_x)`. A struck body is a circle with no spin of its own here, so its
## surface moves with its centre.
func _sliding(state: MatchState, row: int) -> float:
	return _relative(state, row, -_ny[row], _nx[row])


## Relative velocity of side a's contact point over side b's along (`dx`, `dy`):
## the same authoritative point velocity as every contact — the body, the
## combat heading's turn, θ̇ and the attack track's `C′(θ)`.
func _relative(state: MatchState, row: int, dx: float, dy: float) -> float:
	var a := state.fighter(_a[row])
	var pose_a := _poses[a.slot]
	WeaponKinematics.velocity_into(a, pose_a, _px[row], _py[row])
	var bvx := 0.0
	var bvy := 0.0
	if _b_turns(row):
		var b := state.fighter(_b[row])
		var pose_b := _poses[b.slot]
		WeaponKinematics.velocity_into(b, pose_b, _px[row], _py[row])
		bvx = pose_b.vx
		bvy = pose_b.vy
	elif _b_moves(row):
		var body := state.fighter(_b[row])
		bvx = body.vx
		bvy = body.vy
	return (pose_a.vx - bvx) * dx + (pose_a.vy - bvy) * dy


func _apply_velocity(state: MatchState, row: int, impulse: float) -> void:
	if _is_stop_row(row):
		var fighter := row - ROW_STOP
		var turn := -_stop_side[fighter] * impulse / _sword_inertia[fighter]
		_fighters[fighter].weapon.speed += turn
		weapon_delta[fighter] += turn
		return
	_apply_impulse(state, row, impulse, _nx[row], _ny[row], _lever_a[row], _lever_b[row])


func _apply_tangent(state: MatchState, row: int, impulse: float) -> void:
	_apply_impulse(state, row, impulse, -_ny[row], _nx[row], _tangent_a[row], _tangent_b[row])


## `impulse` along (`dx`, `dy`) on side a and its reaction on side b, through
## each side's body mass and, on a sword, its lever over its held inertia.
func _apply_impulse(state: MatchState, row: int, impulse: float, dx: float, dy: float, lever_a: float, lever_b: float) -> void:
	var a := state.fighter(_a[row])
	var jx := impulse * dx
	var jy := impulse * dy
	a.vx += jx * _inverse_mass_a[row]
	a.vy += jy * _inverse_mass_a[row]
	var turn_a := impulse * lever_a / _inertia_a[row]
	a.weapon.speed += turn_a
	weapon_delta[a.slot] += turn_a
	if not _b_moves(row):
		return
	var b := state.fighter(_b[row])
	b.vx -= jx * _inverse_mass_b[row]
	b.vy -= jy * _inverse_mass_b[row]
	if _b_turns(row):
		var turn_b := impulse * lever_b / _inertia_b[row]
		b.weapon.speed -= turn_b
		weapon_delta[b.slot] -= turn_b


func _apply_position(state: MatchState, row: int, pseudo: float) -> void:
	if _is_stop_row(row):
		var fighter := row - ROW_STOP
		var sword := _fighters[fighter].weapon
		sword.angle = clampf(sword.angle - _stop_side[fighter] * pseudo / _sword_inertia[fighter], -_guard_limit[fighter], _guard_limit[fighter])
		return
	var a := state.fighter(_a[row])
	var jx := pseudo * _nx[row]
	var jy := pseudo * _ny[row]
	a.x += jx * _inverse_mass_a[row]
	a.y += jy * _inverse_mass_a[row]
	a.weapon.angle = clampf(a.weapon.angle + pseudo * _lever_a[row] / _inertia_a[row], -_guard_limit[_a[row]], _guard_limit[_a[row]])
	if not _b_moves(row):
		return
	var b := state.fighter(_b[row])
	b.x -= jx * _inverse_mass_b[row]
	b.y -= jy * _inverse_mass_b[row]
	if _b_turns(row):
		b.weapon.angle = clampf(b.weapon.angle - pseudo * _lever_b[row] / _inertia_b[row], -_guard_limit[_b[row]], _guard_limit[_b[row]])
