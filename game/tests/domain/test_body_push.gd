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
	_rules = DuelFixture.rules()


## --- Detection ---------------------------------------------------------------


func test_overlapping_bodies_detected_as_body_push() -> void:
	var state := DuelFixture.state(_rules)
	var radius := _rules.fighter.body_radius
	## Weapons angled perpendicular so neutral blades do not overlap bodies
	## (COMBAT-010: neutral blades can now produce body contacts).
	var a := ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(90.0))
	var b := ContactFixture.pose(radius * 1.5, 0.0, PI, deg_to_rad(90.0))
	var start := ContactFixture.poses(a, b)
	var pair := ContactPairState.new()
	pair.set_phase(ContactPairState.Phase.CONTACTING)
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
	var pair := ContactPairState.new()
	pair.set_phase(ContactPairState.Phase.CONTACTING)
	var report := ContactReport.new()
	_collision.detect(state, start, start, _rules, pair, report)
	assert_false(report.body_push, "far-apart bodies produce no push")


func test_blade_contact_outranks_body_push() -> void:
	var state := DuelFixture.state(_rules)
	var a := ContactFixture.pose(0.0, 0.0, 0.0, 0.0)
	var b := ContactFixture.pose(0.52, 0.0, PI, 0.0)
	var start := ContactFixture.poses(a, b)
	var pair := ContactPairState.new()
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
	var pair := ContactPairState.new()
	pair.set_phase(ContactPairState.Phase.CONTACTING)
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
	var ke_before := 0.5 * _rules.fighter.mass * a.vx * a.vx
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var ke_after := 0.5 * _rules.fighter.mass * (a.vx * a.vx + b.vx * b.vx)
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
	var body_radius := _rules.fighter.body_radius
	var limit := _rules.arena_radius - body_radius
	var light := 40.0
	var heavy := 120.0
	var a_before := a.x
	var b_before := b.x
	ArenaConstraints.separate(a, b, body_radius, limit, light, heavy)
	var gap := SimMath.length(b.x - a.x, b.y - a.y)
	assert_near(gap, body_radius * 2.0, 1e-6, "bodies pushed apart to contact distance")
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
	var body_radius := _rules.fighter.body_radius
	var limit := _rules.arena_radius - body_radius
	var a_before := a.x
	var b_before := b.x
	ArenaConstraints.separate(a, b, body_radius, limit, 80.0, 80.0)
	var a_moved := absf(a.x - a_before)
	var b_moved := absf(b.x - b_before)
	assert_near(a_moved, b_moved, 1e-9, "equal-mass separation moves both by the same amount")
	assert_near(a.vx - b.vx, 0.0, 1e-9, "equal-mass velocity correction is symmetric")


## --- CCD: body-body tunneling during burst -----------------------------------


func test_body_push_detected_during_fast_approach() -> void:
	var state := DuelFixture.state(_rules)
	var radius := _rules.fighter.body_radius
	var far := radius * 3.0
	## Weapons angled perpendicular so neutral blades do not overlap bodies.
	var a := ContactFixture.pose(0.0, 0.0, 0.0, deg_to_rad(90.0))
	var b := ContactFixture.pose(far, 0.0, PI, deg_to_rad(90.0))
	var a_close := ContactFixture.pose(far * 0.5, 0.0, 0.0, deg_to_rad(90.0))
	var start := ContactFixture.poses(a, b)
	var finish := ContactFixture.poses(a_close, b)
	var pair := ContactPairState.new()
	pair.set_phase(ContactPairState.Phase.CONTACTING)
	var report := ContactReport.new()
	_collision.detect(state, start, finish, _rules, pair, report)
	assert_true(report.body_push, "CCD catches body overlap during a fast approach")
	assert_between(report.fraction, 0.01, 0.99, "contact found at an intermediate fraction")


## --- Version -----------------------------------------------------------------


func test_tick_order_version_bumped_for_body_push() -> void:
	assert_eq(DuelSimulation.TICK_ORDER_VERSION, 8, "body push in contact loop bumps tick order")
