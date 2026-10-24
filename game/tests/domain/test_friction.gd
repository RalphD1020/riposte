extends TestCase

## FRICTION: Coulomb friction on held contacts (BLADE-FRICTION-001,
## RIGID-CONTACT-003). The laws, not a feel target: μ = 0 applies no tangent
## impulse; the accumulated tangent impulse never leaves `±μ·Jn`; a slide that
## asks for more than the cone keeps sliding; one inside it stops; more normal
## impulse means more grip; a separating contact has none; a warm start reads
## only the same geometric feature and never the position stage's
## pseudo-impulse; and the whole thing mirrors.
##
## The scenes are a held blade-on-blade X (two diagonal guards about a
## centimetre into each other) and a sword lying across a living torso, solved
## by the real persistent-contact solver from a constructed state.
##
## See also: /docs/reference/testing.md
## See also: /docs/concepts/combat.md

const TIGHT := 1.0e-12
## How deep the crossed guards of `_crossed` overlap (m).
const CROSSED_OVERLAP := 0.01
## How far apart the guards of the walk-in scene start (m).
const WALK_IN_GAP := 0.08

var _rules: DuelRules


func _init() -> void:
	suite_name = "FRICTION"
	_rules = DuelFixture.rules()


## Two diagonal guards crossed in an X, held, overlapping about a centimetre,
## mirrored by `side` (x → −x). Fighter 0 walks into the contact at `press` and
## slides across it at `slide` (m/s, along the contact tangent). `offset` moves
## fighter 1 sideways (toward −x for `side` +1), breaking the scene's point
## symmetry so the contact's normal and tangent rows couple.
func _crossed(press: float, slide: float, side: float = 1.0, rules: DuelRules = null, offset: float = 0.0) -> MatchState:
	var use := rules if rules != null else _rules
	var state := DuelFixture.state(use)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, side * deg_to_rad(45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, use.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), -side * offset, ContactFixture.crossed_guard_separation(use.combatant(0), -CROSSED_OVERLAP, side, -side * offset), -PI / 2.0, side * deg_to_rad(-45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, use.combatant(0).weapon)
	state.blade_contact.set_phase(SwordContactSet.Phase.CONTACTING)
	var frame := _blade_frame(state, use)
	var a := state.fighter(0)
	a.vx = -press * frame[2] + slide * frame[4]
	a.vy = -press * frame[3] + slide * frame[5]
	return state


## [px, py, nx, ny, tx, ty] of the blades' closest points: n from blade 1
## toward blade 0, t = (−n_y, n_x).
func _blade_frame(state: MatchState, rules: DuelRules = null) -> PackedFloat64Array:
	var spec := (rules if rules != null else _rules).combatant(0)
	var w := spec.weapon
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var contact := SegmentContact.new()
	SimMath.closest_segments(
		a.point_x(w.blade_base_radius), a.point_y(w.blade_base_radius), a.point_x(w.tip_radius), a.point_y(w.tip_radius),
		b.point_x(w.blade_base_radius), b.point_y(w.blade_base_radius), b.point_x(w.tip_radius), b.point_y(w.tip_radius),
		contact
	)
	var nx := contact.ax - contact.bx
	var ny := contact.ay - contact.by
	var length := SimMath.length(nx, ny)
	nx /= length
	ny /= length
	return PackedFloat64Array([(contact.ax + contact.bx) * 0.5, (contact.ay + contact.by) * 0.5, nx, ny, -ny, nx])


## Blade 0's point velocity over blade 1's at the contact, along (dx, dy).
func _relative(state: MatchState, frame: PackedFloat64Array, dx: float, dy: float) -> float:
	var spec := _rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	WeaponKinematics.velocity_into(state.fighter(0), a, frame[0], frame[1])
	WeaponKinematics.velocity_into(state.fighter(1), b, frame[0], frame[1])
	return (a.vx - b.vx) * dx + (a.vy - b.vy) * dy


## Solve the tick's first held velocity stage; returns [Jn, Jt] of the blade row.
func _solve(state: MatchState, rules: DuelRules = null) -> PackedFloat64Array:
	RigidContactSolver.new().solve_velocity(state, rules if rules != null else _rules, true)
	return PackedFloat64Array([state.blade_contact.hold_normal[0], state.blade_contact.hold_tangent[0]])


func _frictionless() -> DuelRules:
	var rules := DuelFixture.rules()
	rules.materials.set_friction(MaterialCatalog.STEEL, MaterialCatalog.STEEL, 0.0)
	rules.materials.set_friction(MaterialCatalog.STEEL, MaterialCatalog.FLESH, 0.0)
	return rules


func test_frictionless_holds_apply_no_tangent_impulse() -> void:
	var rules := _frictionless()
	var state := _crossed(0.8, 2.0, 1.0, rules)
	var frame := _blade_frame(state, rules)
	var before := [state.fighter(0).vx, state.fighter(0).vy]
	var slide := _relative(state, frame, frame[4], frame[5])
	assert_true(absf(slide) > 1.0, "fixture: the blades slide across each other (%.2f m/s)" % slide)
	var solved := _solve(state, rules)
	assert_true(solved[0] > 0.0, "the press takes a normal impulse (%.3f N·s)" % solved[0])
	assert_eq(solved[1], 0.0, "μ = 0 ⇒ Jt = 0 exactly")
	## The whole body impulse is along the normal: nothing pushed it sideways.
	var dvx := state.fighter(0).vx - float(before[0])
	var dvy := state.fighter(0).vy - float(before[1])
	assert_true(absf(dvx * frame[2] + dvy * frame[3]) > 0.0, "fighter 0's body takes the normal impulse")
	assert_near(dvx * frame[4] + dvy * frame[5], 0.0, TIGHT, "and none along the tangent")


func test_a_fast_slide_saturates_the_cone_and_keeps_sliding() -> void:
	var state := _crossed(0.6, 3.0)
	var frame := _blade_frame(state)
	var before := _relative(state, frame, frame[4], frame[5])
	var solved := _solve(state)
	var after := _relative(state, frame, frame[4], frame[5])
	assert_true(solved[0] > 0.0, "fixture: the press loads the contact (%.3f N·s)" % solved[0])
	assert_near(absf(solved[1]), _rules.blade_pair().friction * solved[0], TIGHT, "the accumulated tangent impulse sits on the Coulomb bound μ·Jn")
	assert_true(signf(after) == signf(before) and absf(after) > 0.5, "and the blades keep sliding the same way (%.2f → %.2f m/s)" % [before, after])
	assert_true(absf(after) < absf(before), "slower than before: friction took some of it")
	assert_true(signf(solved[1]) == -signf(before), "friction opposes the slide")


func test_a_slow_slide_inside_the_cone_sticks() -> void:
	var state := _crossed(1.5, 0.05)
	var frame := _blade_frame(state)
	assert_true(absf(_relative(state, frame, frame[4], frame[5])) > 0.01, "fixture: a small slide")
	var solved := _solve(state)
	assert_true(absf(solved[1]) < _rules.blade_pair().friction * solved[0], "inside the cone (|%.4f| < μ·%.4f)" % [solved[1], solved[0]])
	assert_near(_relative(state, frame, frame[4], frame[5]), 0.0, 1e-9, "a demand inside the cone stops the slide")


## The cone is μ·Jn, so the same slide under a harder press is gripped
## harder, and under a lighter one less: pressure is what friction spends.
func test_pressure_sets_what_friction_can_take() -> void:
	var light := _crossed(0.3, 3.0)
	var heavy := _crossed(1.2, 3.0)
	var light_solved := _solve(light)
	var heavy_solved := _solve(heavy)
	assert_true(heavy_solved[0] > light_solved[0], "fixture: the harder press has more normal impulse (%.3f vs %.3f N·s)" % [heavy_solved[0], light_solved[0]])
	assert_true(absf(heavy_solved[1]) > absf(light_solved[1]), "so friction takes more (%.4f vs %.4f N·s)" % [absf(heavy_solved[1]), absf(light_solved[1])])
	for solved: PackedFloat64Array in [light_solved, heavy_solved]:
		assert_true(absf(solved[1]) <= _rules.blade_pair().friction * solved[0] + TIGHT, "and neither leaves its cone")


func test_a_separating_contact_has_no_friction() -> void:
	var state := _crossed(-0.8, 3.0)
	var a := state.fighter(0)
	var before := [a.vx, a.vy, a.weapon.speed, state.fighter(1).weapon.speed]
	var solved := _solve(state)
	assert_eq(solved[0], 0.0, "parting blades take no normal impulse")
	assert_eq(solved[1], 0.0, "and therefore no friction, however fast they slide")
	assert_eq([a.vx, a.vy, a.weapon.speed, state.fighter(1).weapon.speed], before, "nothing moves")


## Geometric separation removes the contact and its friction at once: the
## next first solve finds no row and clears the warm-start record, with no timer.
func test_geometric_separation_removes_friction_immediately() -> void:
	var state := _crossed(0.8, 2.0)
	_solve(state)
	assert_eq(state.blade_contact.hold_active[0], 1, "fixture: the held contact is recorded")
	state.fighter(1).y += 0.2
	state.fighter(0).vx = 0.0
	state.fighter(0).vy = 0.0
	var solved := _solve(state)
	assert_eq(state.blade_contact.hold_active[0], 0, "once the blades are apart nothing is held")
	assert_eq(solved, PackedFloat64Array([0.0, 0.0]), "and nothing is warm-started into them")
	assert_eq([state.fighter(0).vx, state.fighter(0).vy], [0.0, 0.0], "so nothing pulls them back")


## A sword lying across the opponent's torso, the opponent pressing into it
## at `press` and walking along it at `slide`.
func _on_torso(press: float, slide: float) -> MatchState:
	var state := DuelFixture.state(_rules)
	var weapon := _rules.combatant(0).weapon
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var offset := _rules.combatant(0).fighter.hurt_radius + weapon.blade_radius - 0.001
	ContactFixture.arm(state.fighter(1), 1.1, offset, PI, deg_to_rad(-135.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	state.weapon_body_contacts[0].phase = WeaponBodyContact.Phase.CONSTRAINING
	state.fighter(1).vy = -press
	state.fighter(1).vx = slide
	return state


func test_a_sword_on_a_torso_grips_far_less_than_on_a_blade() -> void:
	assert_true(_rules.sword_body_pair(0).friction < _rules.blade_pair().friction, "fixture: cloth and flesh grip less than steel")
	var state := _on_torso(0.5, 2.0)
	var target := state.fighter(1)
	RigidContactSolver.new().solve_velocity(state, _rules, true)
	var lifecycle := state.weapon_body_contacts[0]
	assert_true(lifecycle.hold_normal > 0.0, "fixture: the torso presses on the sword (%.3f N·s)" % lifecycle.hold_normal)
	assert_near(absf(lifecycle.hold_tangent), _rules.sword_body_pair(0).friction * lifecycle.hold_normal, TIGHT, "the slide saturates the body's cone")
	assert_true(target.vx > 1.5, "so the body keeps sliding along the blade (%.2f m/s)" % target.vx)
	assert_true(lifecycle.hold_slip > 1.5, "and the reading says it slides (%.2f m/s)" % lifecycle.hold_slip)


## Place hold record 0 at the blades' current touching point, as last tick's
## solve would have (CONTACT-IDENTITY-001 matches by blade fractions), moved
## `shift` along both blades.
func _hold_where_touching(state: MatchState, shift: float = 0.0) -> void:
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var a := WeaponKinematics.pose_of(state.fighter(0), spec, BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), spec, BladePose.new())
	var geometry := SwordContactGeometry.new()
	geometry.measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)
	var contact := state.blade_contact
	contact.hold_fraction_a[0] = geometry.point_fraction_a[geometry.nearest] + shift
	contact.hold_fraction_b[0] = geometry.point_fraction_b[geometry.nearest] + shift


## A warm start is only for the same contact point — the same place along the
## two blades: a record from a point farther away than one tick's match leaves
## the solve exactly cold.
## A warm start can change the result only while friction is inside its cone
## (a saturated slide ends at μ·Jn whatever it started from) and the normal
## and tangent rows couple (uncoupled, each exact projection lands in one
## pass). A symmetric X meets tip to tip with its rows uncoupled, so the scene
## is shifted off that symmetry.
const WARM_SLIDE := 0.1
const WARM_OFFSET := 0.05


func test_a_warm_start_reads_only_the_same_point() -> void:
	var probe := _crossed(0.8, WARM_SLIDE, 1.0, null, WARM_OFFSET)
	var unsaturated := _solve(probe)
	assert_true(unsaturated[0] > 0.0, "fixture: the press loads the contact (%.4f N·s)" % unsaturated[0])
	assert_true(absf(unsaturated[1]) < _rules.blade_pair().friction * unsaturated[0], "fixture: the cold slide stays inside the cone (|%.4f| < μ·%.4f)" % [unsaturated[1], unsaturated[0]])
	var cold := _crossed(0.8, WARM_SLIDE, 1.0, null, WARM_OFFSET)
	var foreign := _crossed(0.8, WARM_SLIDE, 1.0, null, WARM_OFFSET)
	foreign.blade_contact.hold_active[0] = 1
	foreign.blade_contact.hold_normal[0] = 9.0
	foreign.blade_contact.hold_tangent[0] = 1.5
	## PERTURB: the record sits farther along the blades than one tick's match.
	_hold_where_touching(foreign, SwordContactSet.MATCH_DISTANCE)
	_solve(cold)
	_solve(foreign)
	for slot in 2:
		var c := cold.fighter(slot)
		var f := foreign.fighter(slot)
		assert_eq([f.vx, f.vy, f.weapon.speed], [c.vx, c.vy, c.weapon.speed], "slot %d: another point's record changes nothing" % slot)
	## The same point's record is used, and the solve still lands inside the
	## same laws: non-closing, inside the cone.
	var warm := _crossed(0.8, WARM_SLIDE, 1.0, null, WARM_OFFSET)
	warm.blade_contact.hold_active[0] = 1
	warm.blade_contact.hold_normal[0] = 9.0
	warm.blade_contact.hold_tangent[0] = 1.5
	_hold_where_touching(warm)
	var solved := _solve(warm)
	var frame := _blade_frame(warm)
	assert_ne(warm.fighter(0).vx, cold.fighter(0).vx, "a matching record is a warm start")
	assert_true(_relative(warm, frame, frame[2], frame[3]) >= -1e-9, "and it is still a hold, not a pull (%s m/s)" % str(_relative(warm, frame, frame[2], frame[3])))
	assert_true(absf(solved[1]) <= _rules.blade_pair().friction * solved[0] + TIGHT, "inside the cone")


func test_the_position_stage_never_feeds_the_warm_start() -> void:
	var state := _crossed(0.0, 0.0)
	state.blade_contact.hold_active[0] = 1
	state.blade_contact.hold_normal[0] = 0.25
	state.blade_contact.hold_tangent[0] = -0.04
	var before := [state.fighter(0).x, state.fighter(0).y]
	RigidContactSolver.new().project(state, _rules)
	assert_ne([state.fighter(0).x, state.fighter(0).y], before, "fixture: the position stage cleared overlap")
	assert_eq(state.blade_contact.hold_normal[0], 0.25, "its pseudo-impulse is never recorded as normal impulse")
	assert_eq(state.blade_contact.hold_tangent[0], -0.04, "nor as friction")


func test_friction_mirrors_exactly() -> void:
	var right := _crossed(0.7, 2.5, 1.0)
	var left := _crossed(0.7, -2.5, -1.0)
	var r := _solve(right)
	var l := _solve(left)
	assert_true(absf(r[1]) > 0.0, "fixture: friction acts")
	assert_near(l[0], r[0], 1e-9, "the mirrored press takes the same normal impulse")
	assert_near(l[1], -r[1], 1e-9, "and the reflected tangent impulse")
	for slot in 2:
		var rf := right.fighter(slot)
		var lf := left.fighter(slot)
		assert_near(lf.vx, -rf.vx, 1e-9, "slot %d: reflected lateral velocity" % slot)
		assert_near(lf.vy, rf.vy, 1e-9, "slot %d: the same velocity along the line" % slot)
		assert_near(lf.weapon.speed, -rf.weapon.speed, 1e-9, "slot %d: reflected θ̇" % slot)


## Through the real tick: a held contact's identity is geometric
## (CONTACT-IDENTITY-001), so a contact sliding along the blades keeps its
## identity (and its warm start) while the point migrates.
func test_a_held_slide_keeps_its_identity_while_the_point_migrates() -> void:
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, deg_to_rad(45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(state.fighter(1), 0.0, ContactFixture.crossed_guard_separation(spec, WALK_IN_GAP), -PI / 2.0, deg_to_rad(-45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	for fighter in state.fighters:
		fighter.weapon.swing_dir = -signf(fighter.weapon.angle)
	var on_blades := 0
	var warm_ticks := 0
	var lowest := INF
	var highest := -INF
	var identity := -1
	var kept := 0
	for _tick in 40:
		runner.push(PlayerCommand.create(state.tick, 0.6, 0.8), PlayerCommand.idle(state.tick))
		var manifold := state.blade_contact
		if manifold.hold_active[0] == 0 or manifold.point_count == 0:
			continue
		on_blades += 1
		## The same contact, tick after tick: persisted, under one id.
		if manifold.is_persisted(0) and manifold.contact_id[0] == identity:
			kept += 1
		identity = manifold.contact_id[0]
		## Where the point sits on the two blades together (each in [0, 1]).
		var where := manifold.fraction_a[0] + manifold.fraction_b[0]
		lowest = minf(lowest, where)
		highest = maxf(highest, where)
		if manifold.hold_normal[0] > 0.0:
			warm_ticks += 1
	assert_true(on_blades >= 10, "fixture: the blades are held blade on blade while fighter 0 presses and slides (%d ticks)" % on_blades)
	assert_true(warm_ticks >= 5, "and the hold carries real impulse into the next tick (%d ticks)" % warm_ticks)
	assert_true(kept >= 5, "under one contact identity (%d ticks kept it)" % kept)
	assert_true(highest - lowest > 0.05, "while the contact point migrates along the blade (%.3f → %.3f)" % [lowest, highest])


## Footwork reaches friction: sliding sideways along a held blade is now
## resisted, and the resistance is the opponent's blade being dragged along.
func test_lateral_footwork_drags_the_held_blade() -> void:
	var still := _crossed(0.8, 0.0)
	var stepping := _crossed(0.8, 2.0)
	var still_b := still.fighter(1)
	var stepping_b := stepping.fighter(1)
	_solve(still)
	var solved := _solve(stepping)
	var frame := _blade_frame(stepping)
	assert_true(absf(solved[1]) > 0.0, "the lateral step draws a tangent impulse (%.4f N·s)" % solved[1])
	var dragged := (stepping_b.vx - still_b.vx) * frame[4] + (stepping_b.vy - still_b.vy) * frame[5]
	assert_true(dragged > 0.0, "which pulls the opponent the way the step went (%.4f m/s)" % dragged)
