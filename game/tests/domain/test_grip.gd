extends TestCase

## GRIP: steel is blade on blade and each guard root against the other blade
## from its protected side, never guard on guard (STEEL-TOPOLOGY-001,
## GUARD-PROTECTION-001); the handle and the hands are the grip region — hurt
## geometry that can be struck but never blocks (GRIP-NONBLOCKING-001). The
## blade collision capsule is the authoritative blade
## (BLADE-COLLISION-PARITY-001), and a grip reached after steel is judged on
## the trajectory the clash leaves, never shielded.
##
## Scenes are on the product Long Guard: fighter 1 at the origin facing +x with
## its sword at θ = 0; fighter 0's blade comes in square across fighter 1's
## sword, tip first, at a point `along` metres from its pommel, from `from` to
## `to` metres off that sword's axis.
##
## See also: /docs/reference/testing.md
## See also: /docs/concepts/combat.md

var _rules: DuelRules
var _live := {}


func _init() -> void:
	suite_name = "GRIP"
	_rules = DuelFixture.rules()


# ── fixtures ─────────────────────────────────────────────────────────────────


## The world point `along` metres down fighter 1's Long Guard sword from its
## pommel and `across` it (+ toward perp(û)).
func _on_sword(rules: DuelRules, along: float, across: float) -> Vector2:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, rules.combatant(1), BladePose.new())
	return Vector2(held.point_x(along) - held.uy * across, held.point_y(along) + held.ux * across)


## Fighter 0's pose with its blade square across fighter 1's sword, its tip at
## (`along`, `across`) in fighter 1's sword frame.
func _square_pose(rules: DuelRules, along: float, across: float) -> FighterPose:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, rules.combatant(1), BladePose.new())
	var direction := atan2(-held.ux, held.uy)
	var tip := _on_sword(rules, along, across)
	var reach := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, rules.combatant(0), BladePose.new())
	var spec := rules.combatant(0)
	return ContactFixture.pose(tip.x - reach.point_x(spec.weapon.tip_radius), tip.y - reach.point_y(spec.weapon.tip_radius), direction, 0.0, spec)


## [start, finish] of a square cut at `along`, its tip `from` → `to` off the
## axis (fighter 1 standing).
func _square_cut(rules: DuelRules, along: float, from: float, to: float) -> Array:
	var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, rules.combatant(1))
	return [
		ContactFixture.poses(_square_pose(rules, along, from), target),
		ContactFixture.poses(_square_pose(rules, along, to), target),
	]


## A state standing at `poses`, fighter 0 closing at `speed` (m/s) along its cut.
func _state_at(rules: DuelRules, poses: Array[FighterPose], speed: float) -> MatchState:
	var state := DuelFixture.state(rules)
	for slot in 2:
		DuelFixture.place(state.fighter(slot), poses[slot].x, poses[slot].y, poses[slot].facing)
		state.fighter(slot).weapon.angle = 0.0
	state.fighter(0).vx = cos(poses[0].facing) * speed
	state.fighter(0).vy = sin(poses[0].facing) * speed
	return state


## Stand fighter 0 at sweep fraction `s` between `start` and `finish` (the cut
## translates only).
func _seek(state: MatchState, start: Array[FighterPose], finish: Array[FighterPose], s: float) -> void:
	state.fighter(0).x = lerpf(start[0].x, finish[0].x, s)
	state.fighter(0).y = lerpf(start[0].y, finish[0].y, s)


## The blades' surface gap and fighter 0's blade's gap to fighter 1's grip,
## with the fighters at `poses`.
func _gaps(rules: DuelRules, poses: Array[FighterPose]) -> Vector2:
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, rules.combatant(1), BladePose.new())
	var weapon := rules.combatant(0).weapon
	var steel := SwordContactGeometry.new().measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, rules.combatant(1).weapon)
	var grip := InitiativeModel.grip_gap_at(a.point_x(weapon.blade_base_radius), a.point_y(weapon.blade_base_radius), a.point_x(weapon.tip_radius), a.point_y(weapon.tip_radius), weapon.blade_radius, b, 0.0, 0.0, rules.combatant(1), SegmentContact.new())
	return Vector2(steel, grip)


func _count(events: Array[DuelEvent], type: StringName) -> int:
	return DuelFixture.of_type(events, type).size()


# ── STEEL-TOPOLOGY-001 ───────────────────────────────────────────────────────


## Steel is three pairs — blade on blade, and each sword's blade on the
## other's guard root — of at most two points each; there is no guard-on-guard
## pair, and the held solver has a row for every point the set can hold. A tip
## resting on the quillon from the blade's side is steel; the same tip under
## the quillon, on the grip side, or lying level with the bar itself is not;
## the same tip on the blade is.
func test_steel_is_the_blades_and_each_guard_on_its_protected_side() -> void:
	## ARRANGE
	var weapon := _rules.combatant(1).weapon
	var blade_r := _rules.combatant(0).weapon.blade_radius
	var touching := weapon.crossguard_radius + blade_r - 0.001
	var inside := weapon.crossguard_half_span * 0.8
	assert_true(weapon.crossguard_half_span > 3.0 * (weapon.crossguard_radius + blade_r), "fixture: the crossguard reaches well out past the blade (%.3f m)" % weapon.crossguard_half_span)
	## ACT: a tip on the quillon from above, from below and level with it, and
	## on the blade.
	var above := _square_cut(_rules, weapon.crossguard_centre_radius + touching, inside, inside)
	var below := _square_cut(_rules, weapon.crossguard_centre_radius - touching, inside, inside)
	var level := _square_cut(_rules, weapon.crossguard_centre_radius, inside, inside)
	var on_blade := _square_cut(_rules, (weapon.blade_base_radius + weapon.tip_radius) * 0.5, 2.0 * blade_r - 0.001, 2.0 * blade_r - 0.001)
	## ASSERT
	assert_eq(SwordContactSet.PAIRS, 3, "three pairs: blade on blade, and each blade on the other guard — never guard on guard")
	assert_eq(SwordContactSet.CAPACITY, SwordContactSet.PAIRS * SwordContactSet.POINTS_PER_PAIR, "at most two points a pair")
	assert_eq(RigidContactSolver.BLADE_ROWS, SwordContactSet.CAPACITY, "and the held solver a row for each")
	assert_eq(_side(above[0]), 1, "fixture: from above the tip comes from the protected side")
	assert_true(_gaps(_rules, above[0]).x < 0.0, "a tip resting on the quillon from the blade's side is steel (%.4f m)" % _gaps(_rules, above[0]).x)
	assert_eq(_side(below[0]), -1, "fixture: from below it comes from the grip side")
	assert_true(_gaps(_rules, below[0]).x > 0.0, "the same tip under the quillon is not steel (%.4f m)" % _gaps(_rules, below[0]).x)
	assert_eq(_side(level[0]), 0, "fixture: level with the bar it is within the bar's own thickness")
	assert_true(_gaps(_rules, level[0]).x > 0.0, "and there it is never protection (%.4f m)" % _gaps(_rules, level[0]).x)
	assert_true(_gaps(_rules, on_blade[0]).x < 0.0, "the same tip on the blade is steel (%.4f m)" % _gaps(_rules, on_blade[0]).x)


## Which side of fighter 1's guard fighter 0's blade comes from at `poses`.
func _side(poses: Array[FighterPose]) -> int:
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	var blade := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place(a.origin_x, a.origin_y, a.ux, a.uy, _rules.combatant(0).weapon, blade)
	return SwordContactGeometry.guard_side(b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(1).weapon, blade)


## Two crossguards lying across each other, the blades well apart: guard on
## guard is never steel — no point, no gap — so two guards can never hook.
func test_two_crossguards_never_meet() -> void:
	## ARRANGE: fighter 1 in Long Guard at the origin; fighter 0's sword
	## pointing square across it, its bar laid over fighter 1's quillon.
	var weapon := _rules.combatant(1).weapon
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var bar_1 := Vector2(held.point_x(weapon.crossguard_centre_radius), held.point_y(weapon.crossguard_centre_radius))
	var square := WeaponKinematics.pose_at(0.0, 0.0, PI / 2.0, 0.0, _rules.combatant(0), BladePose.new())
	var bar_0 := Vector2(square.point_x(weapon.crossguard_centre_radius), square.point_y(weapon.crossguard_centre_radius))
	var wanted := bar_1 + Vector2(0.10, weapon.crossguard_half_span * 0.8)
	var poses := ContactFixture.poses(ContactFixture.pose(wanted.x - bar_0.x, wanted.y - bar_0.y, PI / 2.0, 0.0, _rules.combatant(0)), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var guard_0 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var guard_1 := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place_guard(a.origin_x, a.origin_y, a.ux, a.uy, weapon, guard_0)
	SwordContactGeometry.place_guard(held.origin_x, held.origin_y, held.ux, held.uy, weapon, guard_1)
	var bars := SegmentContact.new()
	SimMath.closest_segments(guard_0[0], guard_0[1], guard_0[2], guard_0[3], guard_1[0], guard_1[1], guard_1[2], guard_1[3], bars)
	assert_true(bars.distance < 2.0 * weapon.crossguard_radius, "fixture: the two crossbars lie across each other (%.4f m apart)" % bars.distance)
	## ACT
	var geometry := SwordContactGeometry.new()
	var b := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var gap := geometry.measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, weapon, weapon)
	## ASSERT
	assert_true(gap > 0.0 and _all_apart(geometry), "crossguard on crossguard is no steel (least steel gap %.4f m)" % gap)


static func _all_apart(geometry: SwordContactGeometry) -> bool:
	for point in geometry.count:
		if geometry.point_gap[point] <= 0.0:
			return false
	return true


## The guard root is a deliberate approximation, and its envelope is pinned:
## how far its steel reaches beyond the drawn sword (the crossbar and the
## blade, at their own thickness, as the authored model has them) — at most
## the bar's own half-depth, its rounded edge, which is what the root's rise is
## derived from — and nowhere on the grip side of the bar. (A first rules-52
## root rose half its half-span with edges at the blade's thickness and stood
## out 5.4 cm in the corner: steel the player cannot see.)
func test_the_guard_root_reaches_no_further_than_its_corner() -> void:
	## ARRANGE
	var weapon := _rules.combatant(1).weapon
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var guard := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	assert_true(SwordContactGeometry.place_guard(held.origin_x, held.origin_y, held.ux, held.uy, weapon, guard), "fixture: the product sword has a crossguard")
	var bar := SegmentContact.new()
	var blade := SegmentContact.new()
	var worst := 0.0
	var lowest := INF
	## ACT: along both slanted edges, how far the root's surface stands out
	## beyond the nearer of the drawn bar and the drawn blade.
	for edge: Array in [[2, 4], [4, 0]]:
		for k in 201:
			var t := float(k) / 200.0
			var px := lerpf(guard[edge[0]], guard[edge[1]], t)
			var py := lerpf(guard[edge[0] + 1], guard[edge[1] + 1], t)
			SimMath.closest_segments(px, py, px, py, guard[0], guard[1], guard[2], guard[3], bar)
			SimMath.closest_segments(px, py, px, py, held.point_x(weapon.blade_base_radius), held.point_y(weapon.blade_base_radius), held.point_x(weapon.tip_radius), held.point_y(weapon.tip_radius), blade)
			var beyond := minf(bar.distance - weapon.crossguard_radius, blade.distance - weapon.blade_radius) + weapon.crossguard_radius
			worst = maxf(worst, beyond)
			lowest = minf(lowest, (px - held.origin_x) * held.ux + (py - held.origin_y) * held.uy)
	## ASSERT
	assert_true(worst > 0.0, "fixture: the root does fill the corner (%.4f m)" % worst)
	assert_true(worst <= weapon.crossguard_radius + 1.0e-9, "the root's steel stands out at most the bar's half-depth beyond the drawn sword (%.4f m, half-depth %.4f m)" % [worst, weapon.crossguard_radius])
	assert_true(lowest >= weapon.crossguard_centre_radius - 1.0e-9, "and none of it lies on the grip side of the bar (lowest %.4f m, bar at %.4f m)" % [lowest, weapon.crossguard_centre_radius])


## Two wandering duels, every live tick read once for the suite: steel ticks,
## the most points or held rows ever, the farthest a point strays off either
## blade, soundness, and every event.
func _live_duels() -> Dictionary:
	if not _live.is_empty():
		return _live
	var held := 0
	var guarded := 0
	var crowded := 0
	var most := 0
	var outside := 0.0
	var sound := true
	var events: Array[DuelEvent] = []
	for seed_value: int in [3, 5, 9]:
		var runner := SimRunner.create(_rules, seed_value)
		var pilots: Array[Pilot] = [Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23)]
		for _tick in 1800:
			if runner.state.is_finished():
				break
			runner.push(pilots[0].command(runner.state, 0), pilots[1].command(runner.state, 1))
			var contact := runner.state.blade_contact
			if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
				continue
			most = maxi(most, maxi(contact.point_count, contact.hold_count()))
			held += 1 if contact.point_count > 0 else 0
			guarded += 1 if _any_guard_point(contact) else 0
			crowded += 1 if _most_in_a_pair(contact) > SwordContactSet.POINTS_PER_PAIR else 0
			for point in contact.point_count:
				outside = maxf(outside, maxf(absf(contact.fraction_a[point] - SimMath.clamp01(contact.fraction_a[point])), absf(contact.fraction_b[point] - SimMath.clamp01(contact.fraction_b[point]))))
		sound = sound and runner.is_sound()
		events.append_array(runner.events)
	_live = {"held": held, "guarded": guarded, "crowded": crowded, "most": most, "outside": outside, "sound": sound, "events": events}
	return _live


static func _any_guard_point(contact: SwordContactSet) -> bool:
	for point in contact.point_count:
		if contact.pair[point] != SwordContactSet.PAIR_BLADES:
			return true
	return false


static func _most_in_a_pair(contact: SwordContactSet) -> int:
	var counts := PackedInt32Array([0, 0, 0])
	for point in contact.point_count:
		counts[contact.pair[point]] += 1
	return maxi(counts[0], maxi(counts[1], counts[2]))


## Every manifold live play produces is at most two points a steel pair and
## never more than the set holds, each at a place along both blades (a guard
## point at the guard's own fraction, 0), and the solver never holds more.
func test_live_manifolds_are_two_points_a_pair_at_most() -> void:
	## ARRANGE + ACT: the live duels, every tick read.
	var live := _live_duels()
	## ASSERT
	assert_true(int(live["held"]) > 50, "fixture: the duels touch steel (%d ticks)" % int(live["held"]))
	assert_true(int(live["guarded"]) > 0, "fixture: and a guard root among it (%d ticks)" % int(live["guarded"]))
	assert_true(int(live["most"]) <= SwordContactSet.CAPACITY, "no manifold or hold record ever has more points than the set holds (%d)" % int(live["most"]))
	assert_eq(int(live["crowded"]), 0, "nor more than two in any one pair")
	assert_eq(float(live["outside"]), 0.0, "each at a place along both blades")
	assert_true(bool(live["sound"]), "every tick legal")


## PARRY-001 / CONTACT-OUTCOME-001 from the other side: a parry is only ever a
## reading of a solved steel contact. In the live duels every PARRY lands on a
## tick with a BLADE_CONTACT (blade on blade, or a blade on a guard root from
## its protected side) whose attacker is the parried fighter and whose
## solve arrested that fighter's cut, and the parrier is the other fighter —
## no parry without the steel that made it, and no grip ever makes one.
func test_every_parry_is_an_arrested_steel_contact() -> void:
	## ARRANGE + ACT: the live duels' events.
	var events: Array[DuelEvent] = _live_duels()["events"]
	var parries := 0
	var unexplained := PackedStringArray()
	for event in events:
		if event.type != DuelEventTypes.PARRY:
			continue
		parries += 1
		var explained := false
		for clash in events:
			if clash.type != DuelEventTypes.BLADE_CONTACT or clash.tick != event.tick or clash.actor != event.target:
				continue
			var arrested := DuelEventKeys.ARRESTED_0 if event.target == 0 else DuelEventKeys.ARRESTED_1
			explained = explained or (bool(clash.data[arrested]) and event.actor == 1 - event.target)
		if not explained:
			unexplained.append("tick %d" % event.tick)
	## ASSERT
	assert_true(parries >= 5, "fixture: the duels parry (%d)" % parries)
	assert_eq(unexplained.size(), 0, "every parry is an arrested steel contact (%s)" % ", ".join(unexplained))


# ── BLADE-COLLISION-PARITY-001 ───────────────────────────────────────────────


## The rigid capsule is the authoritative blade: its ends are the posed
## blade's own points (the guard root's apex and the point), and the contact
## points it finds are points of the posed blades at their fractions — read
## back by projection on the pose's own direction — on the curved attack
## track, every θ and φ.
func test_the_blade_capsule_is_the_authoritative_blade() -> void:
	## ARRANGE
	var spec := _rules.combatant(0)
	var weapon := spec.weapon
	assert_false(spec.handling.attack_path.is_fixed(), "fixture: the product sword rides a curved track")
	var segment := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var geometry := SwordContactGeometry.new()
	var pose_a := BladePose.new()
	var pose_b := BladePose.new()
	var ends := 0.0
	var points := 0.0
	var touched := 0
	for theta: float in [-weapon.guard_limit, -1.2, -0.45, 0.0, 0.3, 0.9, weapon.guard_limit]:
		for phi: float in [0.0, 0.7, -2.4]:
			## ACT: the capsule placed on the authoritative pose.
			WeaponKinematics.pose_at(0.3, -0.2, phi, theta, spec, pose_a)
			SwordContactGeometry.place(pose_a.origin_x, pose_a.origin_y, pose_a.ux, pose_a.uy, weapon, segment)
			ends = maxf(ends, maxf(
				SimMath.length(segment[0] - pose_a.point_x(weapon.guard_root_apex_radius()), segment[1] - pose_a.point_y(weapon.guard_root_apex_radius())),
				SimMath.length(segment[2] - pose_a.point_x(weapon.tip_radius), segment[3] - pose_a.point_y(weapon.tip_radius))
			))
			## A second sword crossing this one at mid-blade, touching.
			var r := (weapon.blade_base_radius + weapon.tip_radius) * 0.5
			var mid := Vector2(pose_a.point_x(r), pose_a.point_y(r))
			var across := phi + theta + PI / 2.0
			var lift := 2.0 * weapon.blade_radius - 0.001
			var rest := WeaponKinematics.pose_at(0.0, 0.0, across, 0.0, spec, BladePose.new())
			var bx := mid.x - pose_a.uy * lift - rest.point_x(r)
			var by := mid.y + pose_a.ux * lift - rest.point_y(r)
			WeaponKinematics.pose_at(bx, by, across, 0.0, spec, pose_b)
			if geometry.measure(0.3, -0.2, pose_a.origin_x, pose_a.origin_y, pose_a.ux, pose_a.uy, pose_b.origin_x, pose_b.origin_y, pose_b.ux, pose_b.uy, weapon, weapon) > 0.0:
				continue
			touched += 1
			var along_a := SimMath.mix(weapon.blade_base_radius, weapon.tip_radius, geometry.fraction_a)
			var along_b := SimMath.mix(weapon.blade_base_radius, weapon.tip_radius, geometry.fraction_b)
			points = maxf(points, maxf(
				SimMath.length(geometry.ax - pose_a.point_x(along_a), geometry.ay - pose_a.point_y(along_a)),
				SimMath.length(geometry.bx - pose_b.point_x(along_b), geometry.by - pose_b.point_y(along_b))
			))
	## ASSERT
	assert_true(touched >= 15, "fixture: the crossing touches at almost every pose (%d)" % touched)
	assert_eq(ends, 0.0, "the capsule's ends are the posed blade's own points")
	assert_true(points <= 1.0e-12, "the contact points are points of the posed blades at their fractions (%s m)" % String.num_scientific(points))


## The velocity a blade point is solved with is the motion the sweep carries
## it through: `WeaponKinematics.velocity_into` against a central difference
## of `pose_at`, at every 0.5° sample of the attack track and every midpoint
## between, at the blade's base, middle and tip, turning and walking. Measured
## worst at rules 51: 7.3e-6 relative, at the centreline; the bound is 1e-4.
## The root-pivot stick — rotation about the body with no track — misses the
## same motion by 0.21 or more, so the bound tells the two apart a thousandfold.
func test_a_blade_point_moves_as_the_sweep_moves_it() -> void:
	## ARRANGE
	var spec := _rules.combatant(0)
	var weapon := spec.weapon
	var path := spec.handling.attack_path
	assert_false(path.is_fixed(), "fixture: the product sword rides a curved track")
	var h := 1.0e-6
	var step := WeaponAttackPath.DEFAULT_STEP * 0.5
	var worst := 0.0
	var stick := INF
	var samples := 0
	var theta := -weapon.guard_limit + step
	while theta < weapon.guard_limit - step:
		for phi: float in [0.0, -2.4]:
			for along: float in [weapon.blade_base_radius, (weapon.blade_base_radius + weapon.tip_radius) * 0.5, weapon.tip_radius]:
				for motion: Vector4 in [Vector4(0.8, -0.5, 1.1, 6.0), Vector4(-1.2, 0.4, -0.6, -14.0)]:
					var fighter := FighterState.new()
					DuelFixture.place(fighter, 0.3, -0.2, phi)
					fighter.weapon.angle = theta
					fighter.vx = motion.x
					fighter.vy = motion.y
					fighter.turn_rate = motion.z
					fighter.weapon.speed = motion.w
					## ACT
					var pose := WeaponKinematics.pose_at(0.3, -0.2, phi, theta, spec, BladePose.new())
					var px := pose.point_x(along)
					var py := pose.point_y(along)
					WeaponKinematics.velocity_into(fighter, pose, px, py)
					var ahead := WeaponKinematics.pose_at(0.3 + motion.x * h, -0.2 + motion.y * h, phi + motion.z * h, theta + motion.w * h, spec, BladePose.new())
					var behind := WeaponKinematics.pose_at(0.3 - motion.x * h, -0.2 - motion.y * h, phi - motion.z * h, theta - motion.w * h, spec, BladePose.new())
					var swept := Vector2(ahead.point_x(along) - behind.point_x(along), ahead.point_y(along) - behind.point_y(along)) / (2.0 * h)
					var scale := maxf(swept.length(), 1.0)
					worst = maxf(worst, (Vector2(pose.vx, pose.vy) - swept).length() / scale)
					var omega := motion.z + motion.w
					var pivot := Vector2(motion.x - omega * (py - fighter.y), motion.y + omega * (px - fighter.x))
					stick = minf(stick, (pivot - swept).length() / scale)
					samples += 1
		theta += step
	## ASSERT
	assert_true(samples > 10000, "fixture: every sample and midpoint of the track (%d)" % samples)
	assert_true(worst <= 1.0e-4, "a blade point moves as the sweep moves it (%s relative)" % String.num_scientific(worst))
	assert_true(stick > 1000.0 * 1.0e-4, "and the root-pivot stick would not (%s relative at best)" % String.num_scientific(stick))


# ── GRIP-NONBLOCKING-001 ─────────────────────────────────────────────────────


## Each part of the grip region — either hand, the bare handle between them,
## the pommel end — is entered by a real swept cut and struck once: a GRIP
## wound naming the part, no sword contact, no solver row, no impulse, no
## parry, and nothing held.
func test_each_part_of_the_grip_is_struck_never_blocked() -> void:
	var weapon := _rules.combatant(1).weapon
	var blade := _rules.combatant(0).weapon.blade_radius
	var hand := _rules.combatant(1).fighter.hand_radius + blade
	var handle := weapon.handle_radius + blade
	var parts := {
		DuelEventKeys.SOURCE_HAND_OFF: [weapon.offhand_grip_radius, hand + 0.01, hand - 0.005],
		DuelEventKeys.SOURCE_HAND_DOMINANT: [weapon.dominant_grip_radius, hand + 0.01, hand - 0.005],
		DuelEventKeys.SOURCE_HANDLE: [(weapon.offhand_grip_radius + weapon.dominant_grip_radius) * 0.5, handle + 0.01, handle - 0.005],
		"pommel": [-0.005, handle + 0.01, handle - 0.008],
	}
	for part: String in parts:
		## ARRANGE: the cut, closing at 3 m/s.
		var cut: Array = parts[part]
		var ends := _square_cut(_rules, float(cut[0]), float(cut[1]), float(cut[2]))
		var start: Array[FighterPose] = ends[0]
		var finish: Array[FighterPose] = ends[1]
		var state := _state_at(_rules, finish, 3.0)
		assert_true(_gaps(_rules, start).y > 0.0 and _gaps(_rules, finish).y < 0.0, "%s fixture: the cut enters the grip" % part)
		assert_true(_gaps(_rules, finish).x > 0.0, "%s fixture: and never reaches steel" % part)
		## ACT: the sweep, then the wound at its own instant, then the rest.
		var report := ContactReport.new()
		var collision := CollisionSystem.new()
		collision.begin_tick()
		state.blade_contact.begin_search()
		collision.detect(state, start, finish, _rules, state.blade_contact, report)
		var events: Array[DuelEvent] = []
		var before := state.fighter(1).health
		if report.grip[0]:
			_seek(state, start, finish, report.grip_fraction[0])
			ContactResolver.wound_grip(state, _rules, 0, report.grip_along[0], report.grip_across[0], report.grip_source[0], report.grip_fraction[0], 1, events)
		ContactResolver.resolve(state, report, _rules, 1, report.fraction, events)
		var solver := RigidContactSolver.new()
		var held := solver.solve_velocity(state, _rules, true)
		## ASSERT
		var expected := DuelEventKeys.SOURCE_HANDLE if part == "pommel" else part
		assert_true(report.grip[0], "%s: the cut enters the grip" % part)
		assert_eq(report.grip_source[0], expected, "%s: at the part it reached first" % part)
		assert_false(report.blade, "%s: no steel is met" % part)
		assert_eq(state.blade_contact.point_count, 0, "%s: the swords hold no contact point" % part)
		assert_eq(_count(events, DuelEventTypes.BODY_HIT), 1, "%s: one wound" % part)
		var wound: DuelEvent = DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)[0] if _count(events, DuelEventTypes.BODY_HIT) > 0 else null
		assert_true(wound != null and wound.text(DuelEventKeys.REGION) == DuelEventKeys.REGION_GRIP, "%s: on the grip region" % part)
		assert_true(wound != null and wound.text(DuelEventKeys.SOURCE_REGION) == expected, "%s: naming the part" % part)
		assert_eq(_count(events, DuelEventTypes.BLADE_CONTACT) + _count(events, DuelEventTypes.PARRY), 0, "%s: never a blade contact or a parry" % part)
		assert_eq(held, 0.0, "%s: the held solver finds nothing to hold" % part)
		assert_eq(state.blade_contact.hold_count(), 0, "%s: and records no hold" % part)
		assert_true(state.fighter(1).health < before, "%s: the grip is hurt" % part)
		assert_true(state.fighter(0).weapon.grip_struck, "%s: and this attack's grip episode is spent" % part)


## A cut laid along the crossbar's own line is never protected
## (GUARD-PROTECTION-001: within the bar's thickness is no side): a real swept
## cut across a quillon, and on through the crossbar to the far quillon, meets
## no steel, wounds nothing, and leaves nothing to hold — while the same cut a
## little further down the sword, onto the dominant hand, is struck.
func test_a_cut_along_the_crossbar_is_never_protected() -> void:
	## ARRANGE: across the quillon, from outside it to the far side of the bar.
	var weapon := _rules.combatant(1).weapon
	var blade := _rules.combatant(0).weapon.blade_radius
	var reach := weapon.crossguard_radius + blade
	var ends := _square_cut(_rules, weapon.crossguard_centre_radius, weapon.crossguard_half_span + reach + 0.01, weapon.crossguard_half_span * 0.4)
	var start: Array[FighterPose] = ends[0]
	var finish: Array[FighterPose] = ends[1]
	var state := _state_at(_rules, finish, 3.0)
	assert_true(_gaps(_rules, finish).x > 0.0, "fixture: the cut never reaches the blade")
	var hand := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var dominant := Vector2(hand.point_x(weapon.dominant_grip_radius), hand.point_y(weapon.dominant_grip_radius))
	assert_true(_on_sword(_rules, weapon.crossguard_centre_radius, weapon.crossguard_half_span * 0.4).distance_to(dominant) > _rules.combatant(1).fighter.hand_radius + blade, "fixture: nor a hand")
	## ACT
	var report := ContactReport.new()
	var collision := CollisionSystem.new()
	collision.begin_tick()
	state.blade_contact.begin_search()
	collision.detect(state, start, finish, _rules, state.blade_contact, report)
	var held := RigidContactSolver.new().solve_velocity(state, _rules, true)
	## PERTURB: the same cut, a few centimetres toward the pommel, onto the hand.
	var into_hand := _rules.combatant(1).fighter.hand_radius + blade - 0.005
	var hit := _square_cut(_rules, weapon.dominant_grip_radius, weapon.crossguard_half_span + reach + 0.01, into_hand)
	var control := ContactReport.new()
	var other := CollisionSystem.new()
	other.begin_tick()
	var control_state := _state_at(_rules, hit[1], 3.0)
	control_state.blade_contact.begin_search()
	other.detect(control_state, hit[0], hit[1], _rules, control_state.blade_contact, control)
	## ASSERT
	assert_false(report.any(), "across the crossguard the sweep meets nothing — no steel, no grip")
	assert_eq(state.blade_contact.point_count + state.blade_contact.hold_count(), 0, "and nothing is held")
	assert_eq(held, 0.0, "the held solve has no row")
	assert_true(control.grip[0] and control.grip_source[0] == DuelEventKeys.SOURCE_HAND_DOMINANT, "control: the same cut onto the hand is a grip hit")


## A blade lying parallel to the grip, level with both hands, ties them: the
## part listed first (the off hand) is struck, in the scene and in its mirror,
## whatever the rounding — the choice of part never breaks a reflection.
func test_a_blade_level_with_both_hands_strikes_the_same_hand_in_its_mirror() -> void:
	var weapon := _rules.combatant(1).weapon
	var reach := _rules.combatant(1).fighter.hand_radius + _rules.combatant(0).weapon.blade_radius
	var sources: Array[String] = []
	for side: float in [1.0, -1.0]:
		## ARRANGE: fighter 0's blade anti-parallel alongside fighter 1's grip,
		## its middle level with the middle of the hands, closing sideways.
		var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
		var middle := (weapon.offhand_grip_radius + weapon.dominant_grip_radius) * 0.5
		var lay := WeaponKinematics.pose_at(0.0, 0.0, PI, 0.0, _rules.combatant(0), BladePose.new())
		var r := (_rules.combatant(0).weapon.blade_base_radius + _rules.combatant(0).weapon.tip_radius) * 0.5
		var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1))
		var ends: Array = []
		for lateral: float in [reach + 0.01, reach - 0.004]:
			var x := held.point_x(middle) - lay.point_x(r)
			var y := held.point_y(middle) + side * lateral - lay.point_y(r)
			ends.append(ContactFixture.poses(ContactFixture.pose(x, y, PI, 0.0, _rules.combatant(0)), target))
		var state := _state_at(_rules, ends[1], 3.0)
		## ACT
		var report := ContactReport.new()
		var collision := CollisionSystem.new()
		collision.begin_tick()
		state.blade_contact.begin_search()
		collision.detect(state, ends[0], ends[1], _rules, state.blade_contact, report)
		## ASSERT
		assert_true(report.grip[0], "side %+.0f: the blade enters the grip" % side)
		assert_false(report.blade, "side %+.0f fixture: clear of the blade" % side)
		sources.append(report.grip_source[0])
	assert_eq(sources, [DuelEventKeys.SOURCE_HAND_OFF, DuelEventKeys.SOURCE_HAND_OFF] as Array[String], "level with both hands, the off hand is struck — the same in the mirror")


## One episode per attack: a cut that enters a hand and carries on across the
## handle and into the other hand wounds the grip once; the same attack never
## wounds it again.
func test_one_grip_episode_per_attack() -> void:
	## ARRANGE: a cut along the handle from the off hand toward the crossguard.
	var weapon := _rules.combatant(1).weapon
	var start := ContactFixture.poses(_square_pose(_rules, weapon.offhand_grip_radius, 0.0), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))
	var across := _square_cut(_rules, weapon.offhand_grip_radius, _rules.combatant(1).fighter.hand_radius + 0.03, 0.0)
	var first: Array[FighterPose] = across[0]
	var state := _state_at(_rules, first, 3.0)
	var report := ContactReport.new()
	var collision := CollisionSystem.new()
	collision.begin_tick()
	state.blade_contact.begin_search()
	## ACT: into the off hand, then wounded; then the same attack swept on
	## along the whole handle to the dominant hand.
	collision.detect(state, first, start, _rules, state.blade_contact, report)
	var events: Array[DuelEvent] = []
	ContactResolver.wound_grip(state, _rules, 0, report.grip_along[0], report.grip_across[0], report.grip_source[0], report.grip_fraction[0], 1, events)
	var along := ContactFixture.poses(_square_pose(_rules, weapon.dominant_grip_radius, 0.0), start[1])
	var again := ContactReport.new()
	collision.detect(state, start, along, _rules, state.blade_contact, again)
	## ASSERT
	assert_true(report.grip[0], "fixture: the cut enters the off hand")
	assert_eq(_count(events, DuelEventTypes.BODY_HIT), 1, "one grip wound")
	assert_true(state.fighter(0).weapon.grip_struck, "the episode is spent")
	assert_false(again.grip[0], "the same attack reaching the other hand wounds nothing more")


## A blade resting across the opponent's handle is no sword contact and no
## constraint (TANGLE-FREE-GRIP-001): the opponent drawing its handle out from
## under it — sliding along it, and lifting off it — is swept with nothing
## met, nothing held, nothing struck again, and the held solve and the
## position stage move neither fighter.
func test_a_blade_across_a_handle_drags_nothing() -> void:
	var weapon := _rules.combatant(1).weapon
	for draw: Vector2 in [Vector2(-0.025, 0.0), Vector2(0.0, -0.025)]:
		## ARRANGE: fighter 0's blade lying square across fighter 1's handle,
		## between the hands; fighter 1 drawing its sword out from under it.
		var resting := _square_pose(_rules, (weapon.offhand_grip_radius + weapon.dominant_grip_radius) * 0.5, -0.3)
		var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1))
		var start := ContactFixture.poses(resting, target)
		var finish := ContactFixture.poses(resting, ContactFixture.pose(draw.x, draw.y, 0.0, 0.0, _rules.combatant(1)))
		var state := _state_at(_rules, start, 0.0)
		state.fighter(1).vx = draw.x * float(SimulationTimebase.TICK_RATE)
		state.fighter(1).vy = draw.y * float(SimulationTimebase.TICK_RATE)
		assert_true(_gaps(_rules, start).y < 0.0, "fixture: the blade lies inside the grip region")
		assert_true(_gaps(_rules, start).x > 0.0 and _gaps(_rules, finish).x > 0.0, "fixture: and clear of the blade throughout")
		var before := [state.fighter(0).x, state.fighter(0).y, state.fighter(0).vx, state.fighter(0).vy, state.fighter(0).weapon.speed, state.fighter(1).vx, state.fighter(1).vy, state.fighter(1).weapon.speed]
		## ACT
		var report := ContactReport.new()
		var collision := CollisionSystem.new()
		collision.begin_tick()
		state.blade_contact.begin_search()
		collision.detect(state, start, finish, _rules, state.blade_contact, report)
		var solver := RigidContactSolver.new()
		var held := solver.solve_velocity(state, _rules, true)
		solver.project(state, _rules)
		var after := [state.fighter(0).x, state.fighter(0).y, state.fighter(0).vx, state.fighter(0).vy, state.fighter(0).weapon.speed, state.fighter(1).vx, state.fighter(1).vy, state.fighter(1).weapon.speed]
		## ASSERT
		assert_false(report.any(), "drawn %s: the sweep meets nothing — no steel, no new entry" % str(draw))
		assert_eq(state.blade_contact.point_count + state.blade_contact.hold_count(), 0, "drawn %s: and nothing is held" % str(draw))
		assert_eq(held, 0.0, "drawn %s: the held solve has no row" % str(draw))
		assert_eq(after, before, "drawn %s: neither fighter is pulled, pushed or turned" % str(draw))


# ── chronology, never a shield ───────────────────────────────────────────────


## [start, finish] of a cut that, square across fighter 1's sword just below
## where its blade begins, meets the blade's round start first and the handle a
## few millimetres later, in the same substep; then where it goes next, `on`
## times as far again the same way (negative: back out).
func _steel_then_grip(rules: DuelRules, on: float) -> Array:
	var weapon := rules.combatant(1).weapon
	var blade := rules.combatant(0).weapon.blade_radius
	var below := 0.015
	var along := weapon.blade_base_radius - below
	## The blade's start is touched at this far off the axis, the handle at
	## `handle` — farther and nearer than each other by the geometry.
	var steel := sqrt(pow(weapon.blade_radius + blade, 2.0) - below * below)
	var handle := weapon.handle_radius + blade
	var target := ContactFixture.pose(0.0, 0.0, 0.0, 0.0, rules.combatant(1))
	var from := steel + 0.003
	var to := handle - 0.004
	var start := ContactFixture.poses(_square_pose(rules, along, from), target)
	var finish := ContactFixture.poses(_square_pose(rules, along, to), target)
	var next := ContactFixture.poses(_square_pose(rules, along, to + (to - from) * on), target)
	return [start, finish, next]


## A cut that meets the blade first and the handle after it, inside one
## substep, is not shielded by the steel: the clash is solved first and the
## grip is judged on the trajectory the clash leaves. Carried on into the grip
## it is struck; drawn back out it is not; and nothing is pending past its
## tick.
func test_a_grip_reached_after_steel_is_judged_on_what_the_clash_left() -> void:
	## ARRANGE: on a sword with no crossguard, whose blade starts right beside
	## its handle — with a guard root, the grip side of the bar is never steel,
	## so no straight blade meets steel and then the grip inside one substep.
	var rules := _guardless()
	var into := _steel_then_grip(rules, 0.5)
	var out := _steel_then_grip(rules, -1.5)
	var start: Array[FighterPose] = into[0]
	var finish: Array[FighterPose] = into[1]
	assert_true(CollisionSystem.substep_count(start, finish, rules) == 1, "fixture: one substep")
	var gaps_start := _gaps(rules, start)
	var gaps_finish := _gaps(rules, finish)
	assert_true(gaps_start.x > 0.0 and gaps_start.y > 0.0, "fixture: clear of steel and grip at the start")
	assert_true(gaps_finish.x < 0.0 and gaps_finish.y < 0.0, "fixture: into both by the end")
	var halfway: Array[FighterPose] = ContactFixture.poses(ContactFixture.pose(lerpf(start[0].x, finish[0].x, 0.6), lerpf(start[0].y, finish[0].y, 0.6), start[0].facing, 0.0, rules.combatant(0)), start[1])
	assert_true(_gaps(rules, halfway).x < 0.0 and _gaps(rules, halfway).y > 0.0, "fixture: steel first — the blade is touched while the grip is not")
	var outcomes := {}
	for case: String in ["into", "out", "next tick"]:
		var scene: Array = out if case == "out" else into
		var collision := CollisionSystem.new()
		var state := _state_at(rules, start, 3.0)
		collision.begin_tick()
		state.blade_contact.begin_search()
		var first := ContactReport.new()
		## ACT: the substep meets steel first; then the rest of the sweep.
		collision.detect(state, start, finish, rules, state.blade_contact, first)
		if case == "next tick":
			collision.begin_tick()
		var rest := ContactReport.new()
		collision.detect(state, finish, scene[2], rules, state.blade_contact, rest)
		outcomes[case] = [first.blade, first.grip[0], rest.grip[0], rest.grip_source[0]]
	## ASSERT
	assert_true(outcomes["into"][0], "the clash is the substep's first contact")
	assert_false(outcomes["into"][1], "and the grip behind it is not struck before the clash is solved")
	assert_true(outcomes["into"][2], "carried on into the grip, the cut strikes it")
	assert_eq(outcomes["into"][3], DuelEventKeys.SOURCE_HANDLE, "at the handle")
	assert_false(outcomes["out"][2], "drawn back out, it does not")
	assert_false(outcomes["next tick"][2], "and nothing pending outlives its tick")


## The product rules with a sword that has no crossguard at all.
func _guardless() -> DuelRules:
	var rules := DuelFixture.rules()
	rules.combatant(0).weapon.crossguard_half_span = 0.0
	return rules


# ── GUARD-PROTECTION-001 ─────────────────────────────────────────────────────


## A blade [x0, y0, x1, y1], 0.4 m long, whose centreline crosses fighter 1's
## Long Guard sword axis `along` metres from its pommel at `angle` to it,
## centred `across` off the axis (+ toward perp(û)).
func _crossing(along: float, angle: float, across: float = 0.0) -> PackedFloat64Array:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var centre := _on_sword(_rules, along, across)
	var wx := held.ux * cos(angle) - held.uy * sin(angle)
	var wy := held.uy * cos(angle) + held.ux * sin(angle)
	return PackedFloat64Array([centre.x - wx * 0.2, centre.y - wy * 0.2, centre.x + wx * 0.2, centre.y + wy * 0.2])


## Which side of fighter 1's guard `blade` comes from.
func _side_of(blade: PackedFloat64Array) -> int:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	return SwordContactGeometry.guard_side(held.origin_x, held.origin_y, held.ux, held.uy, _rules.combatant(1).weapon, blade)


## `blade` reflected through fighter 1's sword axis (its mirror on the other
## quillon).
func _reflected(blade: PackedFloat64Array) -> PackedFloat64Array:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	for end in 2:
		var dx := blade[2 * end] - held.origin_x
		var dy := blade[2 * end + 1] - held.origin_y
		var along := dx * held.ux + dy * held.uy
		var across := dx * -held.uy + dy * held.ux
		out[2 * end] = held.origin_x + held.ux * along + held.uy * across
		out[2 * end + 1] = held.origin_y + held.uy * along - held.ux * across
	return out


## The side is where the blade's centreline crosses the sword axis, read as a
## signed distance from the bar: past the bar's thickness toward the point is
## protected, past it toward the pommel is the grip side, and within it — or
## within the numerical tolerance of its edge — is no side, never protection.
## Steep or shallow, from either direction, on either quillon (its mirror),
## the reading is the same; a blade too near parallel to cross stably reads
## its point nearest the bar, and one lying beside the bar is no side.
func test_the_side_is_where_the_blade_line_crosses_the_sword_axis() -> void:
	## ARRANGE
	var weapon := _rules.combatant(1).weapon
	var bar := weapon.crossguard_centre_radius
	var thick := weapon.crossguard_radius
	var tolerance := SwordContactGeometry.SIDE_TOLERANCE
	var crossings := {
		bar + 2.0 * thick: 1,
		bar + thick + 10.0 * tolerance: 1,
		bar + thick + 0.5 * tolerance: 0,
		bar + 0.5 * thick: 0,
		bar: 0,
		bar - thick - 0.5 * tolerance: 0,
		bar - thick - 10.0 * tolerance: -1,
		bar - 2.0 * thick: -1,
	}
	var wrong := PackedStringArray()
	## ACT + ASSERT: square, steep, shallow (just above the parallel limit),
	## each from both directions and mirrored.
	for angle: float in [PI / 2.0, PI / 3.0, PI / 6.0, 0.11]:
		for direction: float in [0.0, PI]:
			for along: float in crossings:
				var blade := _crossing(along, angle + direction)
				for reading: int in [_side_of(blade), _side_of(_reflected(blade))]:
					if reading != int(crossings[along]):
						wrong.append("%.4f m at %.2f rad: %d" % [along - bar, angle + direction, reading])
	assert_eq(wrong.size(), 0, "the side is the crossing's signed distance from the bar (%s)" % ", ".join(wrong))
	## Near parallel (sin 0.03 < PARALLEL_SINE): the centreline would cross far
	## down the grip, but the blade lies above the bar, below it, or beside it.
	var shallow := 0.03
	assert_true(absf(sin(shallow)) < SwordContactGeometry.PARALLEL_SINE, "fixture: too near parallel to cross stably")
	var lying_above := _crossing(bar + 0.30, shallow, 0.05)
	var lying_below := _crossing(bar - 0.30, shallow, 0.05)
	var lying_beside := _crossing(bar, shallow, 0.05)
	assert_eq(_side_of(lying_above), 1, "a blade lying along the sword above the bar comes from the protected side")
	assert_eq(_side_of(_reflected(lying_above)), 1, "and so does its mirror")
	assert_eq(_side_of(lying_below), -1, "below it, from the grip side")
	assert_eq(_side_of(lying_beside), 0, "and one lying beside the bar is no side")


## Fighter 1 standing in Long Guard at the origin after the intro; fighter 0's
## blade square across its sword, pointing away from the axis with its tip
## `across` off it and `along` from its pommel; both swords at rest.
func _drift(along: float, across: float) -> SimRunner:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var direction := atan2(-held.ux, held.uy) + (PI if across < 0.0 else 0.0)
	var tip := _on_sword(_rules, along, across)
	var reach := WeaponKinematics.pose_at(0.0, 0.0, direction, 0.0, _rules.combatant(0), BladePose.new())
	var weapon := _rules.combatant(0).weapon
	ContactFixture.arm(runner.state.fighter(1), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(0), tip.x - reach.point_x(weapon.tip_radius), tip.y - reach.point_y(weapon.tip_radius), direction, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	return runner


## One tick of `runner` with fighter 0 driven at `speed` m/s along fighter 1's
## Long Guard sword (+ toward its point).
func _drive(runner: SimRunner, speed: float) -> void:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	runner.state.fighter(0).vx = held.ux * speed
	runner.state.fighter(0).vy = held.uy * speed
	runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))


## Which side of fighter 1's guard fighter 0's blade is on in `state`.
func _side_in(state: MatchState) -> int:
	var a := WeaponKinematics.pose_of(state.fighter(0), _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), _rules.combatant(1), BladePose.new())
	var blade := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	SwordContactGeometry.place(a.origin_x, a.origin_y, a.ux, a.uy, _rules.combatant(0).weapon, blade)
	return SwordContactGeometry.guard_side(b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(1).weapon, blade)


## The gap from fighter 0's blade to fighter 1's guard root in `state`.
func _guard_gap(state: MatchState) -> float:
	var a := WeaponKinematics.pose_of(state.fighter(0), _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_of(state.fighter(1), _rules.combatant(1), BladePose.new())
	var geometry := SwordContactGeometry.new()
	geometry.measure(state.fighter(0).x, state.fighter(0).y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(0).weapon, _rules.combatant(1).weapon, state.blade_contact.guard_mode)
	return geometry.guard_gap[0]


## The solved contacts on fighter 1's guard in `events`, and the largest
## impulse among them.
static func _guard_contacts(events: Array[DuelEvent]) -> Vector2:
	var count := 0
	var impulse := 0.0
	for event in events:
		if event.type == DuelEventTypes.BLADE_CONTACT and int(event.data[DuelEventKeys.STEEL_PAIR]) == SwordContactSet.PAIR_BLADE_ON_GUARD:
			count += 1
			impulse = maxf(impulse, event.number(DuelEventKeys.IMPULSE))
	return Vector2(count, impulse)


## A blade driven onto the guard from its protected side is stopped by it: a
## solved contact on that guard's pair, with positive impulse, and the blade
## kept on the protected side, never through the guard. The same blade driven
## up from the grip side passes through: no contact on the guard, its pair
## latched PASSING from first touch — still passing once the blade's line is
## already above the bar, so never flipped to a block part-way — and freed
## once it is clear. Both quillons read alike.
func test_the_guard_blocks_its_protected_side_and_passes_the_grip_side() -> void:
	## ARRANGE: 8 m/s carries the blade 13 cm a tick, from 10 cm above the bar
	## down onto it, or from 6 cm below the bar up through it.
	var weapon := _rules.combatant(1).weapon
	var inside := weapon.crossguard_half_span * 0.8
	var speed := 8.0
	var readings: Array = []
	for across: float in [inside, -inside]:
		var above := _drift(weapon.crossguard_centre_radius + 0.10, across)
		var below := _drift(weapon.crossguard_centre_radius - 0.06, across)
		assert_true(_guard_gap(above.state) > 0.0 and _guard_gap(below.state) > 0.0, "fixture: both clear of the guard at the start")
		assert_eq(_side_in(above.state), 1, "fixture: from above the blade comes from the protected side")
		assert_eq(_side_in(below.state), -1, "fixture: from below, from the grip side")
		## ACT: one tick onto the guard; the grip-side blade driven on until its
		## pair is freed (at most four ticks).
		_drive(above, -speed)
		var modes := PackedInt32Array()
		var sides := PackedInt32Array()
		for _tick in 4:
			_drive(below, speed)
			modes.append(below.state.blade_contact.guard_mode[0])
			sides.append(_side_in(below.state))
			if modes[modes.size() - 1] == SwordContactGeometry.GUARD_FREE:
				break
		var blocked := _guard_contacts(above.events)
		var passed := _guard_contacts(below.events)
		var latched_above := false
		for k in modes.size():
			latched_above = latched_above or (modes[k] == SwordContactGeometry.GUARD_PASSING and sides[k] == 1)
		## ASSERT
		assert_true(blocked.x > 0.0 and blocked.y > 0.0, "from the protected side the guard is struck and solved (%d contacts, impulse %.4f)" % [int(blocked.x), blocked.y])
		assert_eq(_side_in(above.state), 1, "and the blade stays on the protected side")
		assert_true(_guard_gap(above.state) >= -ContactGauge.allowed(_rules), "never through the guard (%.4f m)" % _guard_gap(above.state))
		assert_eq(int(passed.x), 0, "from the grip side the blade passes the guard untouched")
		assert_false(modes.has(SwordContactGeometry.GUARD_PROTECTED), "never flipped to a block on the way through (%s)" % str(modes))
		assert_true(latched_above, "still passing once its line is above the bar (%s, sides %s)" % [str(modes), str(sides)])
		assert_eq(modes[modes.size() - 1], SwordContactGeometry.GUARD_FREE, "and freed once it is clear (%s)" % str(modes))
		assert_true(above.is_sound() and below.is_sound(), "every tick legal")
		readings.append([int(blocked.x), snappedf(blocked.y, 1.0e-9), snappedf(_guard_gap(above.state), 1.0e-9), int(passed.x), modes, sides])
	assert_eq(str(readings[0]), str(readings[1]), "and both quillons read alike")


## The steel gap between the swords at `poses`, with each guard pair latched
## as `modes`.
func _steel_gap(poses: Array[FighterPose], modes: PackedInt32Array) -> float:
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	return SwordContactGeometry.new().measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(0).weapon, _rules.combatant(1).weapon, modes)


## A protected guard holds a blade while it is on the protected side or within
## the bar's own band — so the line never jitters — and lets it go once it is
## clearly on the grip side, having slipped off the quillon; a passing guard is
## never steel. (The ship corpus once held a blade that had slid round a
## quillon's end against the bar's underside, a degenerate pin.)
func test_a_protected_guard_lets_go_of_a_blade_that_slips_to_the_grip_side() -> void:
	## ARRANGE: one tip on the quillon from above, level with the bar, below it.
	var weapon := _rules.combatant(1).weapon
	var touching := weapon.crossguard_radius + _rules.combatant(0).weapon.blade_radius - 0.001
	var inside := weapon.crossguard_half_span * 0.8
	var above: Array[FighterPose] = _square_cut(_rules, weapon.crossguard_centre_radius + touching, inside, inside)[0]
	var level: Array[FighterPose] = _square_cut(_rules, weapon.crossguard_centre_radius, inside, inside)[0]
	var below: Array[FighterPose] = _square_cut(_rules, weapon.crossguard_centre_radius - touching, inside, inside)[0]
	assert_eq([_side(above), _side(level), _side(below)], [1, 0, -1], "fixture: above, within the band, and on the grip side")
	var protected := PackedInt32Array([SwordContactGeometry.GUARD_PROTECTED, SwordContactGeometry.GUARD_FREE])
	var passing := PackedInt32Array([SwordContactGeometry.GUARD_PASSING, SwordContactGeometry.GUARD_FREE])
	## ACT + ASSERT
	assert_true(_steel_gap(above, protected) < 0.0, "latched protected, a blade above the bar is held")
	assert_true(_steel_gap(level, protected) < 0.0, "and still held within the bar's band — no jitter at the line")
	assert_true(_steel_gap(below, protected) > 0.0, "clearly on the grip side it is let go")
	for poses: Array[FighterPose] in [above, level, below]:
		assert_true(_steel_gap(poses, passing) > 0.0, "a passing guard is never steel")


## Pairs of points in `contact` that stand for one place (within the
## separation two distinct constraints need, pushing the same way).
static func _duplicates(contact: SwordContactSet) -> int:
	var found := 0
	for i in contact.point_count:
		for j in range(i + 1, contact.point_count):
			var apart := SimMath.length(contact.point_x[i] - contact.point_x[j], contact.point_y[i] - contact.point_y[j])
			var same := contact.point_nx[i] * contact.point_nx[j] + contact.point_ny[i] * contact.point_ny[j] >= SwordContactGeometry.SAME_NORMAL_COSINE
			found += 1 if same and apart < SwordContactGeometry.MIN_POINT_SEPARATION else 0
	return found


## Fighter 0's pose with its blade's point at (`along`, `across`) in fighter
## 1's Long Guard sword frame, the blade running from there back along
## (`dir_along`, `dir_across`) in that frame (+ across toward perp(û)).
func _point_at(along: float, across: float, dir_along: float, dir_across: float) -> FighterPose:
	var held := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, _rules.combatant(1), BladePose.new())
	var tip := _on_sword(_rules, along, across)
	var away := Vector2(held.ux * dir_along - held.uy * dir_across, held.uy * dir_along + held.ux * dir_across).normalized()
	var facing := atan2(-away.y, -away.x)
	var reach := WeaponKinematics.pose_at(0.0, 0.0, facing, 0.0, _rules.combatant(0), BladePose.new())
	var spec := _rules.combatant(0)
	return ContactFixture.pose(tip.x - reach.point_x(spec.weapon.tip_radius), tip.y - reach.point_y(spec.weapon.tip_radius), facing, 0.0, spec)


## The seam of blade and guard root: an attacking point resting in the notch
## between the defender's blade and its guard root's slanted edge, touching
## both from the protected side — two pieces of steel at once, pushing
## different ways. The manifold keeps them as two distinct constraints, never
## two points for one place; pressed into the notch for several real ticks the
## point is held there with no duplicate point, no degenerate pin, overlap
## within the slop, and every tick legal.
func test_the_seam_of_blade_and_guard_root_holds_without_a_pin() -> void:
	## ARRANGE: the point's centre at the blade's reach off the axis and the
	## slanted edge's reach above it (each less 0.5 mm), the blade lying out
	## at slope 0.2 — away from both surfaces.
	var weapon := _rules.combatant(1).weapon
	var r := _rules.combatant(0).weapon.blade_radius
	var bar := weapon.crossguard_centre_radius
	var apex := weapon.guard_root_apex_radius()
	var h := weapon.crossguard_half_span
	var slant := SimMath.length(h, apex - bar)
	var off_blade := weapon.blade_radius + r - 0.0005
	var along := apex + ((weapon.crossguard_radius + r - 0.0005) * slant - off_blade * (apex - bar)) / h
	var poses := ContactFixture.poses(_point_at(along, off_blade, 0.2, 1.0), ContactFixture.pose(0.0, 0.0, 0.0, 0.0, _rules.combatant(1)))
	var a := WeaponKinematics.pose_at(poses[0].x, poses[0].y, poses[0].facing, 0.0, _rules.combatant(0), BladePose.new())
	var b := WeaponKinematics.pose_at(poses[1].x, poses[1].y, poses[1].facing, 0.0, _rules.combatant(1), BladePose.new())
	var geometry := SwordContactGeometry.new()
	geometry.measure(poses[0].x, poses[0].y, a.origin_x, a.origin_y, a.ux, a.uy, b.origin_x, b.origin_y, b.ux, b.uy, _rules.combatant(0).weapon, weapon)
	var pairs := PackedInt32Array()
	for p in geometry.count:
		pairs.append(geometry.point_pair[p])
	assert_eq(_side(poses), 1, "fixture: from the protected side, so the root is steel")
	assert_true(pairs.has(SwordContactSet.PAIR_BLADES) and pairs.has(SwordContactSet.PAIR_BLADE_ON_GUARD), "fixture: touching the blade and the root at once (%s)" % str(pairs))
	## ACT: pressed into the notch for four real ticks.
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	ContactFixture.arm(runner.state.fighter(1), poses[1].x, poses[1].y, poses[1].facing, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(0), poses[0].x, poses[0].y, poses[0].facing, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var duplicates := 0
	var held := 0
	var deepest := 0.0
	for _tick in 4:
		_drive(runner, -1.0)
		duplicates += _duplicates(runner.state.blade_contact)
		held = maxi(held, runner.state.blade_contact.point_count)
		deepest = maxf(deepest, -ContactGauge.blades(_rules, runner.state).x)
	## ASSERT
	assert_eq(_duplicates_in(geometry), 0, "the seam's two constraints are distinct, never one place twice")
	assert_true(held >= 1, "fixture: pressed, the point is held (%d points at most)" % held)
	assert_eq(duplicates, 0, "never two points for one place while it is held")
	assert_eq(runner.simulation.diagnostics.position_guard_hits, 0, "no degenerate pin")
	assert_true(deepest <= ContactGauge.allowed(_rules), "held within the slop (deepest %.4f m)" % deepest)
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())


static func _duplicates_in(geometry: SwordContactGeometry) -> int:
	var found := 0
	for i in geometry.count:
		for j in range(i + 1, geometry.count):
			var apart := SimMath.length((geometry.point_ax[i] + geometry.point_bx[i] - geometry.point_ax[j] - geometry.point_bx[j]) * 0.5, (geometry.point_ay[i] + geometry.point_by[i] - geometry.point_ay[j] - geometry.point_by[j]) * 0.5)
			var same := geometry.point_nx[i] * geometry.point_nx[j] + geometry.point_ny[i] * geometry.point_ny[j] >= SwordContactGeometry.SAME_NORMAL_COSINE
			found += 1 if same and apart < SwordContactGeometry.MIN_POINT_SEPARATION else 0
	return found
