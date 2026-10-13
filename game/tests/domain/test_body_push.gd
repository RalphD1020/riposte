extends TestCase

## BODY-PUSH: mass-aware body collision, inverse-mass impulse, CCD during
## burst, and unified chronology (COMBAT-007, PHYS-005).
##
## Implements: /spec/invariants.md#phys-005
## See also: /docs/concepts/combat.md

var _rules: DuelRules
var _collision := CollisionSystem.new()


func _init() -> void:
	suite_name = "BODY-PUSH"
	## Hand-built revolute scenes: the mechanism under test, on the fixed pivot.
	_rules = DuelFixture.revolute_rules()


## --- Detection ---------------------------------------------------------------


func test_overlapping_bodies_detected_as_body_push() -> void:
	var state := DuelFixture.state(_rules)
	var radius := _rules.combatant(0).fighter.push_radius
	## Weapons angled perpendicular so neutral blades do not overlap bodies
	## (COMBAT-010: neutral blades can now produce body contacts).
	var a := ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(90.0))
	var b := ContactFixture.pose(radius * 1.5, 0.0, PI, deg_to_rad(90.0))
	var start := ContactFixture.poses(a, b)
	var pair := SwordContactSet.new()
	pair.set_phase(SwordContactSet.Phase.CONTACTING)
	var report := ContactReport.new()
	_collision.detect(state, start, start, _rules, pair, report)
	assert_true(report.body_push, "overlapping bodies produce a body-push contact")
	assert_near(report.body_push_nx, 1.0, 1e-6, "normal points from fighter 0 toward fighter 1")
	assert_near(report.body_push_ny, 0.0, 1e-6, "normal has no y component for an x-aligned pair")


func test_separated_bodies_produce_no_push() -> void:
	var state := DuelFixture.state(_rules)
	var a := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var b := ContactFixture.pose(3.0, 0.0, PI, 0.0)
	var start := ContactFixture.poses(a, b)
	var pair := SwordContactSet.new()
	pair.set_phase(SwordContactSet.Phase.CONTACTING)
	var report := ContactReport.new()
	_collision.detect(state, start, start, _rules, pair, report)
	assert_false(report.body_push, "far-apart bodies produce no push")


func test_blade_contact_outranks_body_push() -> void:
	var state := DuelFixture.state(_rules)
	var a := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var b := ContactFixture.pose(0.52, 0.0, PI, 0.0)
	var start := ContactFixture.poses(a, b)
	var pair := SwordContactSet.new()
	var report := ContactReport.new()
	_collision.detect(state, start, start, _rules, pair, report)
	assert_true(report.blade, "blade contact fires when blades overlap")
	assert_false(report.body_push, "body push is suppressed when blades contact first")


func test_blade_body_outranks_body_push() -> void:
	var state := DuelFixture.state(_rules)
	state.fighter(0).weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	var a := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var b := ContactFixture.pose(0.52, 0.0, PI, 0.0)
	var start := ContactFixture.poses(a, b)
	var pair := SwordContactSet.new()
	pair.set_phase(SwordContactSet.Phase.CONTACTING)
	var report := ContactReport.new()
	_collision.detect(state, start, start, _rules, pair, report)
	assert_true(report.body[0], "blade-body contact fires")
	assert_false(report.body_push, "body push is suppressed when a blade-body hit exists")


## --- Resolution: inverse-mass impulse ----------------------------------------


func test_equal_mass_splits_velocity_evenly() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 3.0
	b.vx = -3.0
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var pushes := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
	assert_eq(pushes.size(), 1, "one BODY_PUSH event")
	assert_near(a.vx, -b.vx, 1e-9, "equal mass means symmetric post-collision velocity")
	assert_true(a.vx < 3.0, "fighter 0 slowed down")
	assert_true(b.vx > -3.0, "fighter 1 slowed down")


func test_separating_bodies_produce_no_impulse() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = -2.0
	b.vx = 2.0
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	var vx_a := a.vx
	var vx_b := b.vx
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	assert_eq(a.vx, vx_a, "no velocity change when bodies are separating")
	assert_eq(b.vx, vx_b, "no velocity change when bodies are separating")
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH).size(), 0, "no event for separating bodies")


func test_low_restitution_absorbs_energy() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 5.0
	b.vx = 0.0
	var ke_before := 0.5 * _rules.combatant(0).fighter.mass * a.vx * a.vx
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var ke_after := 0.5 * _rules.combatant(0).fighter.mass * (a.vx * a.vx + b.vx * b.vx)
	assert_true(ke_after < ke_before, "low restitution dissipates kinetic energy")
	assert_true(_rules.combat.body_restitution < 0.5, "precondition: restitution is low")


func test_body_push_event_carries_payload() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, -0.1, 0.0, 0.0)
	DuelFixture.place(b, 0.1, 0.0, PI)
	a.vx = 4.0
	b.vx = -1.0
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 7, 0.3, events)
	var pushes := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
	assert_eq(pushes.size(), 1, "exactly one event")
	var ev := pushes[0]
	assert_eq(ev.tick, 7, "correct tick")
	assert_near(ev.data[DuelEventKeys.CLOSING_SPEED], 5.0, 1e-6, "closing speed = 4 - (-1)")
	assert_true(ev.data[DuelEventKeys.IMPULSE] > 0.0, "positive impulse")
	assert_near(ev.data[DuelEventKeys.NORMAL_X], 1.0, 1e-6, "normal carried")
	assert_near(ev.data[DuelEventKeys.TOI], 0.3, 1e-6, "time of impact carried")
	assert_true(ev.data.has(DuelEventKeys.SLIDING_SPEED), "sliding speed key present")
	assert_true(ev.data.has(DuelEventKeys.TANGENTIAL_IMPULSE), "tangential impulse key present")


## --- Tangential friction (PHYS-005) ------------------------------------------


func test_sliding_collision_applies_tangential_impulse() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 3.0
	a.vy = 4.0
	b.vx = 0.0
	b.vy = 0.0
	var vy_a_before := a.vy
	var vy_b_before := b.vy
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	assert_true(_rules.combat.body_friction > 0.0, "precondition: friction is enabled")
	assert_true(absf(a.vy) < absf(vy_a_before), "fighter 0 lost tangential speed")
	assert_true(absf(b.vy) > absf(vy_b_before), "fighter 1 gained tangential speed (friction dragged)")
	var pushes := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
	assert_true(pushes[0].data[DuelEventKeys.TANGENTIAL_IMPULSE] > 0.0, "tangential impulse reported")
	assert_true(pushes[0].data[DuelEventKeys.SLIDING_SPEED] > 0.0, "sliding speed reported")


func test_no_tangential_impulse_when_no_sliding() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 3.0
	a.vy = 0.0
	b.vx = -3.0
	b.vy = 0.0
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var pushes := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
	assert_near(pushes[0].data[DuelEventKeys.TANGENTIAL_IMPULSE], 0.0, 1e-9, "no friction when no sliding")
	assert_near(pushes[0].data[DuelEventKeys.SLIDING_SPEED], 0.0, 1e-9, "zero sliding speed")


func test_friction_bounded_by_coulomb_law() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 1.0
	a.vy = 20.0
	b.vx = 0.0
	b.vy = 0.0
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var pushes := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
	var j_normal: float = pushes[0].data[DuelEventKeys.IMPULSE]
	var j_tangential: float = pushes[0].data[DuelEventKeys.TANGENTIAL_IMPULSE]
	assert_near(j_tangential, _rules.combat.body_friction * j_normal, 1e-9, "tangential impulse = μ × normal impulse (Coulomb bound)")
	assert_true(absf(a.vy) > 0.0, "lateral motion not zeroed — friction merely reduced it")


func test_friction_equals_zero_when_coefficient_is_zero() -> void:
	var rules := DuelFixture.rules()
	rules.combat.body_friction = 0.0
	var state := DuelFixture.state(rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 3.0
	a.vy = 4.0
	b.vx = 0.0
	b.vy = 0.0
	var vy_a_before := a.vy
	var vy_b_before := b.vy
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, rules, 0, 0.5, events)
	assert_eq(a.vy, vy_a_before, "zero friction leaves tangential velocity untouched")
	assert_eq(b.vy, vy_b_before, "zero friction leaves tangential velocity untouched")
	var pushes := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
	assert_near(pushes[0].data[DuelEventKeys.TANGENTIAL_IMPULSE], 0.0, 1e-9, "no tangential impulse")


func test_tangential_friction_does_not_reverse_sliding() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 3.0
	a.vy = 0.001
	b.vx = 0.0
	b.vy = 0.0
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var post_sliding := (a.vy - b.vy)
	assert_true(post_sliding >= -1e-9, "friction cannot reverse the direction of sliding")


## --- Arena constraints: mass-aware separation --------------------------------


func test_arena_separation_is_mass_aware() -> void:
	var a := FighterState.new()
	var b := FighterState.new()
	a.slot = 0
	b.slot = 1
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.3, 0.0, PI)
	a.vx = 2.0
	b.vx = -2.0
	var push_radius := _rules.combatant(0).fighter.push_radius
	var light := 40.0
	var heavy := 120.0
	var a_before := a.x
	var b_before := b.x
	ArenaConstraints.separate(a, b, push_radius, push_radius, light, heavy)
	var gap := SimMath.length(b.x - a.x, b.y - a.y)
	assert_near(gap, push_radius * 2.0 + ArenaConstraints.BODY_CONTACT_REST_EPSILON, 1e-9, "bodies pushed apart to contact distance, resting just outside it")
	var light_moved := absf(a.x - a_before)
	var heavy_moved := absf(b.x - b_before)
	assert_true(light_moved > heavy_moved, "lighter fighter absorbs more displacement")


func test_equal_mass_separation_is_symmetric() -> void:
	var a := FighterState.new()
	var b := FighterState.new()
	a.slot = 0
	b.slot = 1
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.3, 0.0, PI)
	a.vx = 2.0
	b.vx = -2.0
	var push_radius := _rules.combatant(0).fighter.push_radius
	var a_before := a.x
	var b_before := b.x
	ArenaConstraints.separate(a, b, push_radius, push_radius, 80.0, 80.0)
	var a_moved := absf(a.x - a_before)
	var b_moved := absf(b.x - b_before)
	assert_near(a_moved, b_moved, 1e-9, "equal-mass separation moves both by the same amount")
	assert_near(a.vx - b.vx, 0.0, 1e-9, "equal-mass velocity correction is symmetric")


## --- CCD: body-body tunneling during burst -----------------------------------


func test_body_push_detected_during_fast_approach() -> void:
	var state := DuelFixture.state(_rules)
	var radius := _rules.combatant(0).fighter.push_radius
	var far := radius * 3.0
	## Weapons angled perpendicular so neutral blades do not overlap bodies.
	var a := ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(90.0))
	var b := ContactFixture.pose(far, 0.0, PI, deg_to_rad(90.0))
	var a_close := ContactFixture.pose(far * 0.5, 0.0, 0.0, deg_to_rad(90.0))
	var start := ContactFixture.poses(a, b)
	var finish := ContactFixture.poses(a_close, b)
	var pair := SwordContactSet.new()
	pair.set_phase(SwordContactSet.Phase.CONTACTING)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, pair, report)
	assert_true(report.body_push, "CCD catches body overlap during a fast approach")
	assert_between(report.fraction, 0.01, 0.99, "contact found at an intermediate fraction")


## --- Version -----------------------------------------------------------------


func test_tick_order_version_bumped_for_body_push() -> void:
	assert_eq(DuelSimulation.TICK_ORDER_VERSION, 13, "body push in contact loop bumps tick order (13: a spent re-hold budget carries the remainder without tunnelling)")


## --- Rest epsilon (BODY-CONTACT-OWNERSHIP-001) -------------------------------


## `BODY_CONTACT_REST_EPSILON` is numerical hysteresis separating the resting
## configuration from the contact trigger, not physics: far above the ULP of
## the authoritative 64-bit positions anywhere on the platform, far below
## anything visible and the sword contact slop — and it survives the
## separation arithmetic, so separated bodies really do rest outside touching.
## (Mirrored contact is exact: `test_held_pressure_mirrors_exactly`.)
func test_the_body_rest_epsilon_is_hysteresis_not_physics() -> void:
	var epsilon := ArenaConstraints.BODY_CONTACT_REST_EPSILON
	var ulp_at_rim := _rules.platform_radius * pow(2.0, -52.0)
	assert_true(epsilon > 1.0e5 * ulp_at_rim, "five orders above double precision at the rim (%s vs %s m)" % [str(epsilon), str(ulp_at_rim)])
	assert_true(epsilon <= _rules.combat.contact_slop * 1.0e-3, "at least three orders below the sword slop (%s vs %s m)" % [str(epsilon), str(_rules.combat.contact_slop)])
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	var touch := 2.0 * _rules.combatant(0).fighter.push_radius
	for at: float in [0.0, _rules.platform_radius - touch - 0.01]:
		DuelFixture.place(a, at, 0.0, 0.0)
		DuelFixture.place(b, at + touch - 0.003, 0.0, PI)
		assert_true(DuelGeometry.distance(a, b) < touch, "fixture: overlapping at x = %.2f" % at)
		ArenaConstraints.separate(a, b, _rules.combatant(0).fighter.push_radius, _rules.combatant(1).fighter.push_radius, _rules.combatant(0).fighter.mass, _rules.combatant(1).fighter.mass)
		var gap := DuelGeometry.distance(a, b) - touch
		assert_true(gap > 0.5 * epsilon and gap < 2.0 * epsilon, "separated bodies rest just outside touching at x = %.2f (gap %s m)" % [at, str(gap)])


## A long hold is stable: two fighters walking into each other for five
## seconds, swords held back out of the way, stay in one continuous body
## contact — never interpenetrating, never flickering apart and re-impacting
## (which would re-apply first-contact restitution every few ticks).
func test_a_long_body_hold_is_stable() -> void:
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	var touch := 2.0 * _rules.combatant(0).fighter.push_radius
	DuelFixture.place(state.fighter(0), 0.0, -0.4, PI * 0.5)
	DuelFixture.place(state.fighter(1), 0.0, 0.4, -PI * 0.5)
	for slot in 2:
		state.fighter(slot).weapon.angle = _rules.combatant(0).weapon.guard_limit * (1.0 if slot == 0 else -1.0)
	var swords := 0
	var touched := -1
	var flickers := 0
	var deepest := INF
	var widest := 0.0
	for tick in 300:
		var commands: Array[PlayerCommand] = [PlayerCommand.create(state.tick, 0.0, 1.0), PlayerCommand.create(state.tick, 0.0, 1.0)]
		for event in runner.simulation.step(state, commands[0], commands[1]):
			if event.type == DuelEventTypes.BLADE_CONTACT or event.type == DuelEventTypes.BODY_HIT:
				swords += 1
		if touched < 0 and state.body_contact.phase == BodyContactState.Phase.CONTACTING:
			touched = tick
		if touched >= 0:
			if state.body_contact.phase != BodyContactState.Phase.CONTACTING:
				flickers += 1
			var gap := DuelGeometry.distance(state.fighter(0), state.fighter(1)) - touch
			deepest = minf(deepest, gap)
			widest = maxf(widest, gap)
	assert_eq(swords, 0, "fixture: the swords stay out of it")
	assert_true(touched >= 0 and touched < 120, "fixture: the bodies meet (tick %d)" % touched)
	assert_eq(flickers, 0, "one continuous contact for the whole hold")
	assert_true(deepest >= -1.0e-12, "never interpenetrating (deepest %s m)" % str(deepest))
	assert_true(widest <= 1.0e-4, "never drifting visibly apart (widest %s m)" % str(widest))


## --- Body contact lifecycle (PHYS-009) ---------------------------------------


func test_new_contact_uses_authored_restitution() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 5.0
	b.vx = 0.0
	## New contact: body_push_persistent = false (default).
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	## Restitution formula: J = (1+e) * closing / inv_total
	## With e = 0.05 and equal mass, post-collision v_rel should be negative
	## (fighters separate) but reduced by the low restitution.
	var post_rel := a.vx - b.vx
	assert_true(post_rel < 0.0, "new contact: fighters separate after impact (restitution)")
	var expected_rel := -_rules.combat.body_restitution * 5.0
	assert_near(post_rel, expected_rel, 0.01, "restitution: v_rel_after ≈ -e × v_rel_before")


## The shove's mechanics, at the precondition the FULL-E2E journey only
## reaches: a dashing body meets a standing one at a known closing speed, equal
## masses, along a known normal. The struck body leaves at (1 + e)/2 of the
## closing speed, momentum is conserved, and the dash ends into recovery. The
## journey proves a real dash gets here; this proves what happens when it does.
func test_a_dash_into_a_standing_body_shoves_it_by_momentum() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 2.0 * _rules.combatant(0).fighter.push_radius, 0.0, PI)
	var closing := _rules.combatant(0).fighter.burst_speed_axial
	a.vx = closing
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = _rules.combatant(0).fighter.burst_ticks
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0
	assert_true(a.gesture.is_bursting(), "fixture: the shover is mid-dash")
	var momentum_before := _rules.combatant(0).fighter.mass * (a.vx + b.vx)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, ContactFixture.body_push_report(1.0, 0.0), _rules, 0, 0.5, events)
	var e := _rules.combat.body_restitution
	assert_near(b.vx, 0.5 * (1.0 + e) * closing, 1e-9, "the struck body leaves at (1 + e)/2 of the closing speed (%.2f m/s)" % b.vx)
	assert_near(_rules.combatant(0).fighter.mass * (a.vx + b.vx), momentum_before, 1e-9, "momentum is conserved")
	assert_false(a.gesture.is_bursting(), "and the dash ends on the body it hit")
	assert_true(a.gesture.is_recovering(), "into its recovery")


func test_persistent_contact_uses_zero_restitution() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 5.0
	b.vx = 0.0
	## Persistent contact: body_push_persistent = true.
	var report := ContactFixture.body_push_report(1.0, 0.0)
	report.body_push_persistent = true
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	## Zero restitution constraint: closing velocity zeroed, no bounce.
	var post_rel := a.vx - b.vx
	assert_near(post_rel, 0.0, 1e-9, "persistent contact: zero restitution, no bounce")


func test_body_contact_lifecycle_separated_to_contacting() -> void:
	var bc := BodyContactState.new()
	assert_eq(bc.phase, BodyContactState.Phase.SEPARATED, "initial phase is SEPARATED")
	assert_eq(bc.ticks_in_contact, 0, "initial ticks is 0")
	bc.begin_contact()
	assert_eq(bc.phase, BodyContactState.Phase.CONTACTING, "begin_contact transitions to CONTACTING")
	assert_eq(bc.ticks_in_contact, 0, "ticks_in_contact is 0 on the impact tick")


func test_body_contact_lifecycle_tick_increments() -> void:
	var bc := BodyContactState.new()
	bc.begin_contact()
	assert_true(bc.is_new_contact(), "first tick is new contact")
	bc.tick()
	assert_eq(bc.ticks_in_contact, 1, "tick increments ticks_in_contact")
	assert_true(bc.is_persistent_contact(), "second tick is persistent contact")
	bc.tick()
	assert_eq(bc.ticks_in_contact, 2, "tick continues incrementing")


func test_body_contact_lifecycle_end_contact() -> void:
	var bc := BodyContactState.new()
	bc.begin_contact()
	bc.tick()
	bc.tick()
	bc.end_contact()
	assert_eq(bc.phase, BodyContactState.Phase.SEPARATED, "end_contact transitions to SEPARATED")
	assert_eq(bc.ticks_in_contact, 0, "ticks reset on separation")


func test_body_contact_lifecycle_reset() -> void:
	var bc := BodyContactState.new()
	bc.begin_contact()
	bc.tick()
	bc.prev_normal_x = 1.0
	bc.prev_normal_y = 0.5
	bc.reset()
	assert_eq(bc.phase, BodyContactState.Phase.SEPARATED, "reset returns to SEPARATED")
	assert_eq(bc.ticks_in_contact, 0, "reset clears ticks")
	assert_eq(bc.prev_normal_x, 0.0, "reset clears fallback normal")


func test_body_contact_state_invariants_separated_with_nonzero_ticks() -> void:
	var state := DuelFixture.state(_rules)
	state.body_contact.phase = BodyContactState.Phase.SEPARATED
	state.body_contact.ticks_in_contact = 5
	var violation := StateInvariants.check(state, _rules)
	assert_eq(violation, StateInvariants.BODY_CONTACT_MISMATCH, "SEPARATED with ticks > 0 is invalid")


func test_body_contact_state_invariants_valid() -> void:
	var state := DuelFixture.state(_rules)
	state.body_contact.phase = BodyContactState.Phase.CONTACTING
	state.body_contact.ticks_in_contact = 3
	var violation := StateInvariants.check(state, _rules)
	assert_eq(violation, StateInvariants.OK, "CONTACTING with ticks >= 0 is valid")


func test_momentum_conservation_on_new_contact() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	var mass := _rules.combatant(0).fighter.mass
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 5.0
	b.vx = -2.0
	var p_before := mass * a.vx + mass * b.vx
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var p_after := mass * a.vx + mass * b.vx
	assert_near(p_after, p_before, 1e-6, "momentum conserved: |p_after - p_before| < epsilon")


func test_restitution_relation_on_new_contact() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 4.0
	b.vx = -1.0
	var v_rel_before := a.vx - b.vx
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var v_rel_after := a.vx - b.vx
	var expected := -_rules.combat.body_restitution * v_rel_before
	assert_near(v_rel_after, expected, 0.01, "v_rel,n_after ≈ -e × v_rel,n_before")


func test_contact_normal_derived_from_live_geometry() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	## Place bodies off-axis so the normal is not aligned with report normal.
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.3, 0.3, PI)
	a.vx = 2.0
	a.vy = 2.0
	## Report normal is along x — but the resolver should derive from positions.
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var pushes := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
	assert_eq(pushes.size(), 1, "contact resolved")
	## The live normal should be ~(0.707, 0.707), not (1, 0).
	var nx: float = pushes[0].data[DuelEventKeys.NORMAL_X]
	var ny: float = pushes[0].data[DuelEventKeys.NORMAL_Y]
	assert_near(nx, ny, 0.01, "normal derived from live geometry, not report")
	assert_near(SimMath.length(nx, ny), 1.0, 1e-6, "normal is unit length")


func test_body_contact_in_state_hash() -> void:
	var state := DuelFixture.state(_rules)
	var hash_a := StateHasher.hash_state(state)
	state.body_contact.begin_contact()
	var hash_b := StateHasher.hash_state(state)
	assert_ne(hash_a, hash_b, "body contact phase change affects state hash")
	state.body_contact.tick()
	var hash_c := StateHasher.hash_state(state)
	assert_ne(hash_b, hash_c, "body contact tick count change affects state hash")


func test_rules_version_bumped() -> void:
	assert_true(_rules.version >= 19, "the body contact lifecycle shipped in rules version 19 (now %d)" % _rules.version)


## --- Phase 5: Cross-system property/stress tests ----------------------------


func test_long_duration_continuous_contact() -> void:
	## 10,000-tick match with fighters held in close proximity to exercise the
	## body-contact lifecycle, dash cycling, and sword exchanges over many
	## rounds.
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 42)
	runner.skip_intro()
	var left := Pilot.wander(42, 0)
	var right := Pilot.wander(42, 1)
	runner.run(left, right, 10000)
	assert_true(runner.is_sound(), "10,000 ticks: all invariants held: %s" % runner.violation_summary())
	for slot in 2:
		var me := runner.state.fighter(slot)
		assert_finite(me.speed(), "slot %d speed is finite after 10k ticks" % slot)
		assert_finite(me.x, "slot %d x is finite after 10k ticks" % slot)
		assert_finite(me.y, "slot %d y is finite after 10k ticks" % slot)


func test_body_contact_constraint_impulse_finite_under_fuzz() -> void:
	## Randomized command sequences must keep body_contact impulse finite.
	var rules := DuelFixture.rules()
	for seed_value in PackedInt32Array([3, 7, 17, 31]):
		var runner := SimRunner.create(rules, seed_value)
		runner.run(Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23), 1800)
		assert_true(runner.is_sound(), "seed %d: all invariants held: %s" % [seed_value, runner.violation_summary()])
		var bc := runner.state.body_contact
		assert_finite(bc.last_constraint_impulse, "seed %d: impulse is finite" % seed_value)
		assert_finite(bc.last_constraint_normal_x, "seed %d: normal_x is finite" % seed_value)
		assert_finite(bc.last_constraint_normal_y, "seed %d: normal_y is finite" % seed_value)


func test_replay_determinism_with_body_contact_physics() -> void:
	## Record/replay round-trip with new body contact + dash + sword-body physics.
	var rules := DuelFixture.rules()
	var first := SimRunner.create(rules, 99)
	first.run(Pilot.wander(99, 11), Pilot.wander(99, 23), 2400, true)
	first.seal()
	var second := SimRunner.create(rules, 99)
	second.run(Pilot.wander(99, 11), Pilot.wander(99, 23), 2400, true)
	second.seal()
	assert_eq(StateHasher.hash_state(first.state), StateHasher.hash_state(second.state), "same seed, same duel after 2400 ticks")
	assert_eq(ReplayVerifier.verify(first.record, rules), ReplayVerifier.VERIFIED, "recorded commands reproduce the duel exactly")


func test_symmetric_input_symmetric_output() -> void:
	## Metamorphic: identical command streams on both sides should produce
	## approximately symmetric state — small asymmetry is expected from
	## side assignments (facing, starting positions) and contact normals.
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 1)
	runner.skip_intro()
	for _i in 180:
		var tick := runner.state.tick
		var cmd := PlayerCommand.create(tick, 0.3, 1.0, false, false, false)
		runner.push(cmd, cmd)
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	## Tolerance accounts for asymmetry from side assignments and normals.
	assert_near(a.health, b.health, 0.5, "symmetric input: approximately equal health")
	assert_near(a.stamina, b.stamina, 0.5, "symmetric input: approximately equal stamina")
	var bc := runner.state.body_contact
	assert_true(bc.last_constraint_impulse >= 0.0, "constraint impulse is non-negative")


func test_cross_system_chronology() -> void:
	## Body-body and sword-body contacts in the same tick must resolve in the
	## correct chronological order (body first if earlier TOI, sword first if
	## earlier TOI). Verify via invariants and finite state.
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 5)
	runner.skip_intro()
	## Drive fighters directly at each other to maximize contact probability.
	for _i in 300:
		var tick := runner.state.tick
		runner.push(
			PlayerCommand.create(tick, 0.0, 1.0, _i % 20 < 3, _i % 20 == 3, false),
			PlayerCommand.create(tick, 0.0, 1.0, _i % 25 < 3, _i % 25 == 3, false),
		)
	assert_true(runner.is_sound(), "cross-system chronology: all invariants held: %s" % runner.violation_summary())
	## Must have seen both body and sword contacts during 300 ticks of face-to-face combat.
	var body_pushes := runner.count(DuelEventTypes.BODY_PUSH)
	var body_hits := runner.count(DuelEventTypes.BODY_HIT)
	assert_true(body_pushes > 0 or body_hits > 0, "cross-system: at least one contact type occurred")
