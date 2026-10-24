extends TestCase

## WEDGE: the parallel-blade / tips-in-crossguards configuration (audit
## 2026-10-22). Two equal blades roughly parallel and overlapping, each tip
## beside the other's crossguard, which the single plane registers as one
## two-point blade-blade (lying-along) contact. The audit's question is whether
## this is a mechanical trap or merely tension: the engine is authoritative, so
## the test is whether ORDINARY player input retains a reliable, understandable
## path to disengagement - not merely that release eventually occurs.
##
## These are diagnostics-as-regression: the existing solver resolves the wedge,
## so no production change is made here (no timer, forced separation, friction
## change, or classification change). The suite measures escape PROGRESS and
## full release across a bounded family, and pins replay stability.
##
## See also: /docs/concepts/combat.md

## Separation progress counts once the blade surface gap has opened this far (m)
## past where the wedge started - a real step toward release, not jitter.
const PROGRESS_GAP := 0.01

var _rules: DuelRules


func _init() -> void:
	suite_name = "WEDGE"
	_rules = DuelFixture.rules()


## The blade surface gap now (m); negative while the blades overlap.
func _blades_gap(state: MatchState) -> float:
	return ContactGauge.blades(_rules, state).x


## The symmetric parallel wedge: two equal blades antiparallel and overlapping,
## each tip beside the other's crossguard, optionally splayed by a small angle,
## held by the solver after a few idle ticks.
func _parallel_wedge(offset: float, a_angle: float = 0.0, b_angle: float = 0.0) -> SimRunner:
	var runner := SimRunner.create(_rules, 13)
	runner.skip_intro()
	DuelFixture.place(runner.state.fighter(0), 0.0, 0.0, PI / 2.0)
	runner.state.fighter(0).weapon.reset(a_angle)
	DuelFixture.place(runner.state.fighter(1), offset, 2.344, -PI / 2.0)
	runner.state.fighter(1).weapon.reset(b_angle)
	for _settle in 3:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	return runner


## Drive the two fighters with the given duel-relative intents and measure the
## escape: the tick of first meaningful separation progress, the tick of full
## release (SEPARATED), whether every tick was legal, and what is held at the end.
func _escape(runner: SimRunner, ax: float, ay: float, bx: float, by: float, ticks: int) -> Dictionary:
	var start_gap := _blades_gap(runner.state)
	var progress := -1
	var release := -1
	var legal := true
	for t in ticks:
		runner.push(PlayerCommand.create(runner.state.tick, ax, ay), PlayerCommand.create(runner.state.tick, bx, by))
		legal = legal and runner.is_sound()
		if progress < 0 and _blades_gap(runner.state) > start_gap + PROGRESS_GAP:
			progress = t + 1
		if release < 0 and runner.state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
			release = t + 1
	var contact := runner.state.blade_contact
	return {"progress": progress, "release": release, "legal": legal, "held": contact.hold_count() + contact.point_count}


## The reproduction forms the intended configuration: two equal blades whose
## tips sit at each other's crossguards, in a single two-point blade contact the
## solver holds.
func test_the_symmetric_parallel_wedge_forms() -> void:
	var spec := _rules.combatant(0)
	var w := spec.weapon
	var runner := _parallel_wedge(0.04)
	var pose_a := WeaponKinematics.pose_of(runner.state.fighter(0), spec, BladePose.new())
	var pose_b := WeaponKinematics.pose_of(runner.state.fighter(1), spec, BladePose.new())
	assert_near(pose_a.point_y(w.tip_radius), pose_b.point_y(w.crossguard_centre_radius), 0.05, "A's tip sits at B's crossguard")
	assert_near(pose_b.point_y(w.tip_radius), pose_a.point_y(w.crossguard_centre_radius), 0.05, "and B's tip at A's crossguard")
	assert_true(runner.state.blade_contact.hold_count() > 0, "the parallel bind is held (%d)" % runner.state.blade_contact.hold_count())


## A bind is legal combat. What must not happen is a wedge that ordinary
## movement cannot leave. Resting may keep the swords together. Stepping back
## must take this parallel, tip-against-crossguard wedge apart, with nothing
## still held.
func test_a_resting_wedge_may_stay_bound_and_retreat_unsticks_it() -> void:
	var resting := _escape(_parallel_wedge(0.04), 0.0, 0.0, 0.0, 0.0, 30)
	assert_true(bool(resting.legal), "resting in the wedge stays a legal pose")
	var escape := _escape(_parallel_wedge(0.04), 0.0, -1.0, 0.0, -1.0, 90)
	assert_true(int(escape.release) >= 0 and int(escape.release) <= 75, "stepping back unsticks the wedge (tick %d)" % int(escape.release))
	assert_eq(int(escape.held), 0, "and nothing stays held once the blades are apart")
	assert_true(bool(escape.legal), "every tick of the unstick is legal")


## Ordinary mutual retreat opens the wedge with measurable progress, then fully
## releases it - not a trap. The release tick is recorded (at 60 Hz it is the
## felt escape time; the audit flags that a human must judge whether it feels
## acceptable, which this automated bound does not claim).
func test_both_fighters_retreat_escapes_with_progress() -> void:
	var runner := _parallel_wedge(0.04)
	var escape := _escape(runner, 0.0, -1.0, 0.0, -1.0, 90)
	assert_true(int(escape.progress) >= 0 and int(escape.progress) <= 25, "retreat makes separation progress quickly (tick %d)" % int(escape.progress))
	assert_true(int(escape.release) >= 0 and int(escape.release) <= 75, "and fully releases, not a trap (tick %d)" % int(escape.release))
	assert_true(bool(escape.legal), "every tick is legal")
	assert_eq(int(escape.held), 0, "with no stale hold once apart")


## A bounded family of nearby wedges - closer and wider offsets, and a small
## symmetric and asymmetric angular splay - all make progress and release on
## ordinary mutual retreat. One configuration escaping is not the whole family;
## this samples it.
func test_the_wedge_family_escapes_with_progress() -> void:
	var family := [
		[0.03, 0.0, 0.0],
		[0.045, 0.0, 0.0],
		[0.04, 0.08, -0.08],
		[0.04, 0.08, 0.0],
		[0.035, -0.06, 0.06],
	]
	for config: Array in family:
		var label := "offset %.3f a %.2f b %.2f" % [config[0], config[1], config[2]]
		var runner := _parallel_wedge(config[0], config[1], config[2])
		assert_true(_blades_gap(runner.state) < 0.03, "%s: fixture: the blades start in a wedge (%.4f m)" % [label, _blades_gap(runner.state)])
		var escape := _escape(runner, 0.0, -1.0, 0.0, -1.0, 90)
		assert_true(int(escape.progress) >= 0 and int(escape.progress) <= 30, "%s: retreat makes progress (tick %d)" % [label, int(escape.progress)])
		assert_true(int(escape.release) >= 0 and int(escape.release) <= 85, "%s: and releases (tick %d)" % [label, int(escape.release)])
		assert_true(bool(escape.legal), "%s: every tick legal" % label)
		assert_eq(int(escape.held), 0, "%s: no stale hold" % label)


## Unilateral retreat (one fighter backs off, the other stands) and a lateral
## step both have an escape path: the wedge is not an input-starved lock.
func test_unilateral_retreat_and_a_lateral_step_both_escape() -> void:
	var unilateral := _escape(_parallel_wedge(0.04), 0.0, -1.0, 0.0, 0.0, 90)
	assert_true(int(unilateral.progress) >= 0, "one fighter retreating makes separation progress (tick %d)" % int(unilateral.progress))
	assert_true(int(unilateral.release) >= 0, "and the wedge releases (tick %d)" % int(unilateral.release))
	assert_true(bool(unilateral.legal) and int(unilateral.held) == 0, "legal throughout, nothing stale")
	var lateral := _escape(_parallel_wedge(0.04), 1.0, 0.0, 1.0, 0.0, 90)
	assert_true(int(lateral.progress) >= 0, "a lateral step makes separation progress (tick %d)" % int(lateral.progress))
	assert_true(int(lateral.release) >= 0, "and the wedge releases (tick %d)" % int(lateral.release))
	assert_true(bool(lateral.legal) and int(lateral.held) == 0, "legal throughout, nothing stale")


## The whole press-and-escape is deterministic: the same wedge, the same retreat,
## the same final state.
func test_the_wedge_escape_is_replay_stable() -> void:
	var first := _parallel_wedge(0.04)
	var second := _parallel_wedge(0.04)
	for _t in 90:
		first.push(PlayerCommand.create(first.state.tick, 0.0, -1.0), PlayerCommand.create(first.state.tick, 0.0, -1.0))
		second.push(PlayerCommand.create(second.state.tick, 0.0, -1.0), PlayerCommand.create(second.state.tick, 0.0, -1.0))
	assert_eq(StateHasher.hash_state(first.state), StateHasher.hash_state(second.state), "the press-and-escape is replay-stable")
	assert_eq(first.state.blade_contact.hold_count() + first.state.blade_contact.point_count, 0, "and ends released")
