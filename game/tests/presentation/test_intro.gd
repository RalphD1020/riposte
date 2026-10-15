extends TestCase

## PRES-INTRO: the set intro's motion is real play, replayed. Each fighter's
## shot is recorded through the real simulation (`IntroRehearsal`) — a step in
## from the 45° start guard, a wind-back while walking, a cut — and posed on
## an intro-only figure exactly as the match presenter poses a proxy
## (PRES-INTRO-001).
##
## Implements: /spec/invariants.md#pres-intro-001
## See also: /docs/concepts/presentation.md

const FRAME := 1.0 / 60.0

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-INTRO"
	_rules = StandardDuelRules.create()


## The take starts where the round starts — the 45° guard, not the centre
## line — winds back from it, and releases the cut from there: it sweeps from
## the start side through the centre to the other side. A cut released from
## the centre line (the old flourish's "central stab") fails the release check.
func test_the_take_cuts_from_the_45_degree_start_guard() -> void:
	var guard := _rules.combatant(0).weapon.guard_angle
	for slot in 2:
		var frames := IntroRehearsal.record(_rules, 7, slot)
		assert_eq(frames.size(), IntroRehearsal.TAKE_TICKS + 1, "slot %d: one frame per tick of the take" % slot)
		var start := frames[0].fighter(slot)
		assert_eq(frames[0].phase, MatchPhase.Id.ROUND_ACTIVE, "slot %d: the take begins as the round goes live" % slot)
		assert_near(start.weapon_angle, -guard, 1e-9, "slot %d: from the start guard (%.1f°)" % [slot, rad_to_deg(start.weapon_angle)])
		var released := INF
		var lowest := INF
		var highest := -INF
		var charged := false
		for frame in frames:
			var row := frame.fighter(slot)
			lowest = minf(lowest, row.weapon_angle)
			highest = maxf(highest, row.weapon_angle)
			charged = charged or row.phase == CombatPhase.Id.CHARGING
			if row.phase == CombatPhase.Id.LAUNCH and released == INF:
				released = row.weapon_angle
		assert_true(charged, "slot %d: it winds back before cutting" % slot)
		assert_true(lowest < -guard, "slot %d: past the start guard (%.1f°)" % [slot, rad_to_deg(lowest)])
		assert_true(released < -guard + deg_to_rad(5.0), "slot %d: released from the wound-back start guard, not the centre (%.1f°)" % [slot, rad_to_deg(released)])
		assert_true(highest > deg_to_rad(20.0), "slot %d: the cut crosses the centre to the far side (%.1f°)" % [slot, rad_to_deg(highest)])
		var other := 1 - slot
		var opening := frames[0].fighter(other)
		var closing := frames[-1].fighter(other)
		assert_true(SimMath.length(start.x - opening.x, start.y - opening.y) > SimMath.length(frames[-1].fighter(slot).x - opening.x, frames[-1].fighter(slot).y - opening.y), "slot %d: the fighter steps in" % slot)
		assert_eq(Vector2(closing.x, closing.y), Vector2(opening.x, opening.y), "slot %d: the opponent is never touched" % slot)


## The rehearsal plays on its own throwaway state: recording both takes leaves
## the live match bit-identical, and the live duel then plays exactly as one
## that was never introduced — same hash at the start and after two seconds.
func test_the_rehearsal_never_touches_the_live_match() -> void:
	var simulation := DuelSimulation.create(_rules)
	var live := simulation.new_match(7)
	var control := simulation.new_match(7)
	var opening := StateHasher.hash_state(live)
	assert_eq(StateHasher.hash_state(control), opening, "fixture: two fresh matches of one seed are identical")
	for slot in 2:
		IntroRehearsal.record(_rules, 7, slot)
	assert_eq(StateHasher.hash_state(live), opening, "recording the takes changes nothing in the live match")
	for _tick in 120:
		simulation.step(live, PlayerCommand.idle(live.tick), PlayerCommand.idle(live.tick))
		simulation.step(control, PlayerCommand.idle(control.tick), PlayerCommand.idle(control.tick))
	assert_eq(live.tick, control.tick, "the same tick count")
	assert_eq(StateHasher.hash_state(live), StateHasher.hash_state(control), "and the introduced duel plays exactly as the un-introduced one")


## Recorded, so the same rules always produce the same intro.
func test_the_take_is_deterministic() -> void:
	var first := IntroRehearsal.record(_rules, 7, 0)
	var second := IntroRehearsal.record(_rules, 7, 0)
	assert_eq(first.size(), second.size(), "same length")
	for index in first.size():
		assert_eq(first[index].fighter(0).weapon_angle, second[index].fighter(0).weapon_angle, "same sword at frame %d" % index)


## The director poses its own figures from the takes, interpolated like the
## match presenter: the figure stands where the take says, its planar sword is
## the rehearsal's authoritative sword, its legs play a clip the rig really
## has, and it is never a match proxy.
func test_the_director_poses_intro_figures_from_the_take() -> void:
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	var takes: Array[IntroTake] = [IntroTake.of(IntroRehearsal.record(_rules, 7, 0)), IntroTake.of(IntroRehearsal.record(_rules, 7, 1))]
	var root := (Engine.get_main_loop() as SceneTree).root
	var audio := AudioDirector.new()
	root.add_child(audio)
	var gameplay := Camera3D.new()
	root.add_child(gameplay)
	var stand_in := Node3D.new()
	root.add_child(stand_in)
	var proxies: Array[Node3D] = [stand_in]
	var director := SetIntroDirector.create(kits, takes[0].frames[0], audio, proxies, gameplay, takes)
	root.add_child(director)
	assert_false(stand_in.visible, "the match's own proxies step aside")
	var charge_tick := IntroRehearsal.PRESS_AT + _rules.combatant(0).weapon.tap_threshold_ticks + 4
	var seconds := float(charge_tick) * SimulationTimebase.TICK_SECONDS
	var frames := ceili(seconds / FRAME)
	for _i in frames:
		director.advance(FRAME)
	var elapsed := float(frames) * FRAME
	var take := director.take(0)
	var at := take.index_at(elapsed)
	var weight := take.blend_at(elapsed)
	var from := take.frames[at].fighter(0)
	var row := take.frames[mini(at + 1, take.frames.size() - 1)].fighter(0)
	assert_eq(row.phase, CombatPhase.Id.CHARGING, "fixture: mid wind-back at frame %d" % at)
	var figure := director.figure(0)
	var x := lerpf(from.x, row.x, weight)
	var y := lerpf(from.y, row.y, weight)
	var expected := ArenaTransform.to_world(x, y)
	assert_true(figure.position.distance_to(expected) < 1.0e-3, "the figure stands where the take says (%.4f m off)" % figure.position.distance_to(expected))
	var planar := WeaponKinematics.pose_at(x, y, lerp_angle(from.facing, row.facing, weight), lerpf(from.weapon_angle, row.weapon_angle, weight), _rules.combatant(0), BladePose.new())
	var drawn := figure.authoritative_blade_points()
	var height := kits.weapon.blade_height
	for end: Array in [[0, _rules.combatant(0).weapon.blade_base_radius, "hilt"], [1, _rules.combatant(0).weapon.tip_radius, "tip"]]:
		var truth := ArenaTransform.to_world(planar.point_x(float(end[1])), planar.point_y(float(end[1])), height)
		assert_true(drawn[int(end[0])].distance_to(truth) < 1.0e-3, "the planar sword's %s is the rehearsal's (%.4f m off)" % [end[2], drawn[int(end[0])].distance_to(truth)])
	assert_true(figure.animation_player().has_animation(figure.playing_clip()), "the legs play a clip the rig has (%s)" % figure.playing_clip())
	assert_true(figure != stand_in, "an intro figure, not a match proxy")
	director.finish()
	assert_true(stand_in.visible, "finishing hands the stage back")
	for node: Node in [audio, gameplay, stand_in]:
		node.queue_free()
	await await_frames(1)
