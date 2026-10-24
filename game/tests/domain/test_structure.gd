extends TestCase

## STRUCTURE: swords meet stage structures through the one contact engine
## (STRUCTURE-CONTACT-001, CONTACT-SIDE-001, CONTACT-MATERIAL-001). The Arena's
## stone wall and wooden gates block a blade, it slides along them under the
## same Coulomb law as steel on steel, a held blade does not strike again, and
## nothing a structure does is a hit, a parry, or opponent contact. Stages
## without structures are untouched.
##
## See also: /docs/concepts/combat.md

const SLOP_SLACK := 1.0e-6


func _init() -> void:
	suite_name = "STRUCTURE"


func test_only_the_arena_carries_structures() -> void:
	var pit := StandardDuelRules.pit()
	assert_eq(pit.problem(), "", "the walled pit is valid rules")
	assert_eq(pit.version, 60, "on version 60")
	var ids: Array[StringName] = []
	for structure: StageObjectDef in pit.structures:
		ids.append(structure.object_id)
	assert_eq(ids, [StageStructures.INNER_WALL, StageStructures.GATE_NORTH, StageStructures.GATE_SOUTH], "a stone wall and two gates, in authored order")
	assert_eq(pit.structures[0].material.id, MaterialCatalog.STONE, "the wall is stone")
	assert_eq(pit.structures[1].material.id, MaterialCatalog.WOOD, "the gates are wood")
	assert_eq(pit.structure_pair(0, 0).friction, 0.35, "steel on stone grips 0.35")
	assert_eq(pit.structure_pair(1, 1).friction, 0.45, "steel on wood grips 0.45")
	var open := StandardDuelRules.create()
	assert_true(open.structures.is_empty(), "version 58 has no walls")
	assert_true(StageCatalog.the_end().rules().structures.is_empty(), "The End has no walls")
	assert_eq(DuelSetup.new_state(pit, 1).structure_contacts.size(), 2, "a walled match tracks each sword on the stage")
	assert_eq(DuelSetup.new_state(open, 1).structure_contacts.size(), 0, "a match without walls tracks nothing, so it hashes as before")
	assert_ne(pit.world_fingerprint(), open.world_fingerprint(), "the walls are in the world fingerprint")
	var record := ReplayRecord.begin(pit, 4)
	assert_true(record.matches_rules(pit), "fixture: a recording matches its own rules")
	var moved := StandardDuelRules.pit()
	moved.structures[0].shapes[0].radius = 8.0
	assert_false(record.matches_rules(moved), "and is refused when a wall moved under the same version")
	var broken := StandardDuelRules.pit()
	broken.structures[0].shapes[0].radius = -1.0
	assert_false(broken.is_valid(), "an impossible wall does not start a duel")


## The narrow phase finds the right feature with the right normal: stone to
## the east, the north door in its recess, the jamb at the opening's edge.
func test_the_narrow_phase_names_the_wall_the_gate_and_the_jamb() -> void:
	var rules := StandardDuelRules.pit()
	var blade := rules.combatant(0).weapon.blade_radius
	var geometry := StructureContactGeometry.new()
	geometry.measure(7.5, 0.0, 8.5, 0.0, blade, rules.structures, 0.0)
	assert_eq(geometry.count, 1, "a blade through the east wall touches one feature")
	assert_eq(geometry.structure[0], 0, "the inner wall")
	assert_eq(geometry.shape[0], 1, "its east arc")
	assert_near(geometry.gap[0], 8.27 - 8.5 - blade, 1e-12, "as deep as the tip is past the face")
	assert_near(geometry.normal_x[0], -1.0, 1e-12, "pushed back toward the centre")
	assert_near(geometry.fraction[0], 1.0, 1e-12, "at the tip")
	geometry.measure(0.0, 7.6, 0.0, 8.45, blade, rules.structures, 0.0)
	assert_eq(geometry.count, 0, "inside the opening the stone does not reach the blade")
	assert_near(geometry.least_gap, StageStructures.DOOR_RADIUS - 8.45 - blade, 1e-12, "the door is the nearest thing, a few centimetres on")
	geometry.measure(0.0, 7.6, 0.0, 8.49, blade, rules.structures, 0.0)
	assert_eq(geometry.count, 1, "a tip at the door touches it")
	assert_eq(geometry.structure[0], 1, "the north gate")
	## Inside the recess, the tip just reaching the jamb's plane: past it the
	## stone arc's span begins, and a blade already through stone would read
	## as the deeper arc.
	geometry.measure(0.5, 8.3, StageStructures.GATE_HALF_WIDTH + 0.01, 8.3, blade, rules.structures, 0.0)
	assert_eq(geometry.count, 1, "a blade lying across the opening's edge meets the jamb")
	assert_eq(geometry.shape[0], 2, "the north-east jamb")
	assert_near(absf(geometry.normal_x[0]), 1.0, 1e-9, "whose face is square to the gate axis")
	rules.structures[0].blocks_blade = false
	geometry.measure(7.5, 0.0, 8.5, 0.0, blade, rules.structures, 0.0)
	assert_eq(geometry.count, 0, "a structure that does not block blades is not met")


## The stone arc and the gate jamb meet with no seam: a blade slid along the
## wall across the stone-to-jamb corner is always in contact (no gap to fall
## through) and always on the inner wall, and both the curved stone and the
## straight jamb are reachable. The corner is where the east arc ends and the
## north gate's +x jamb begins, (half, face) by construction, so there is no
## artificial gap or protruding edge there - no invisible barrier, no
## blade-through-stone hole.
func test_the_stone_to_jamb_transition_has_no_seam() -> void:
	var rules := StandardDuelRules.pit()
	var blade := rules.combatant(0).weapon.blade_radius
	var wall := rules.platform_radius
	var half := StageStructures.GATE_HALF_WIDTH
	var face := sqrt(wall * wall - half * half)
	var door := sqrt(StageStructures.DOOR_RADIUS * StageStructures.DOOR_RADIUS - half * half)
	var corner_angle := atan2(face, half)
	## Each sample is a blade reaching its surface from the valid (inner) side:
	## up the east arc toward the corner, then up the jamb from inside the gate
	## opening - the same approach the narrow phase proves.
	var bases: Array[Vector2] = []
	var tips: Array[Vector2] = []
	for step in 6:
		var ang := lerpf(corner_angle - 0.12, corner_angle, float(step) / 5.0)
		var out := Vector2(cos(ang), sin(ang))
		bases.append(out * (wall - 0.15))
		tips.append(out * (wall + 0.01))
	for step in 5:
		var y := lerpf(face + 0.02, door - 0.05, float(step) / 4.0)
		bases.append(Vector2(half - 0.2, y))
		tips.append(Vector2(half + 0.02, y))
	var geometry := StructureContactGeometry.new()
	var seen_arc := false
	var seen_jamb := false
	for i in bases.size():
		geometry.measure(bases[i].x, bases[i].y, tips[i].x, tips[i].y, blade, rules.structures, 0.0)
		assert_true(geometry.count >= 1, "no seam gap at tip (%.3f, %.3f)" % [tips[i].x, tips[i].y])
		assert_eq(geometry.structure[0], 0, "the contact is the inner wall at tip (%.3f, %.3f)" % [tips[i].x, tips[i].y])
		seen_arc = seen_arc or geometry.shape[0] == 1
		seen_jamb = seen_jamb or geometry.shape[0] == 2
	## Both the curved stone and the straight jamb are reachable along the
	## slide, so the opening is bounded by stone on both features with no hole
	## between them - no invisible barrier and no blade-through-stone gap.
	assert_true(seen_arc, "the slide touches the stone arc")
	assert_true(seen_jamb, "and the +x north jamb, with no seam gap between them")


## A static structure is the world side: no inverse mass, no velocity. The
## first impact removes the blade's closing speed through the sword and its
## wielder only, bounces by the pair's restitution, and only loses energy.
func test_the_wall_is_the_world_side_of_one_impulse_law() -> void:
	var rules := StandardDuelRules.pit()
	rules.materials.set_friction(MaterialCatalog.STEEL, MaterialCatalog.STONE, 0.0)
	var scene := _point_on_the_wall(rules, 2.0, 0.0, 0.0)
	var fighter: FighterState = scene[0]
	var contact: StructureContactSet = scene[1]
	var pose: BladePose = scene[2]
	var spec := rules.combatant(0)
	var inertia := ContactMechanics.weapon_inertia(pose, spec)
	var inverse := ContactMechanics.body_inverse_mass(spec)
	var closing := StructureContactSolver.closing_speed(fighter, pose, contact.point_x[0], contact.point_y[0], -1.0, 0.0)
	assert_near(closing, 2.0, 1e-9, "fixture: the blade closes on the stone at 2 m/s")
	var before := StructureContactSolver.kinetic_energy(fighter, inertia, inverse)
	var pairs: Array[ContactPair] = [rules.structure_pair(0, 0)]
	var delta := PackedFloat64Array([0.0])
	var rows := PackedFloat64Array([0.0])
	var impulse := StructureContactSolver.solve(contact, fighter, pose, pairs, inertia, inverse, delta, rows, ContactLcp.new())
	var lever := WeaponKinematics.lever(fighter, pose, contact.point_x[0], contact.point_y[0], -1.0, 0.0)
	var k := lever * lever / inertia + inverse
	var e := pairs[0].restitution_at(2.0)
	## The block is regularized by 1e-6 on its diagonal (RigidContactSolver).
	assert_near(impulse / ((1.0 + e) * 2.0 / k), 1.0, 1.0e-5, "J = (1 + e)·v_n / k with k the wielder's side alone")
	assert_near(StructureContactSolver.closing_speed(fighter, pose, contact.point_x[0], contact.point_y[0], -1.0, 0.0), -e * 2.0, 1.0e-4, "the blade leaves the stone at e × the closing speed")
	assert_true(StructureContactSolver.kinetic_energy(fighter, inertia, inverse) <= before + 1e-12, "and the solve only took energy out")
	var away := _point_on_the_wall(rules, -2.0, 0.0, 0.0)
	var none := StructureContactSolver.solve(away[1], away[0], away[2], pairs, inertia, inverse, delta, rows, ContactLcp.new())
	assert_eq(none, 0.0, "a blade moving away from the wall takes no impulse")
	assert_eq((away[1] as StructureContactSet).tangent_impulse[0], 0.0, "and no friction")


## Sliding along stone: the tangent impulse sits inside the Coulomb cone, a
## fast slide keeps sliding and slows, a slow one inside the cone sticks. The
## tip slides because the sword is turning (θ̇ across the wall) while it rests
## on the stone with little pressure — a body walked sideways is cheap for the
## sword to absorb by turning, so it would stick.
func test_a_blade_slides_or_sticks_on_stone_by_the_coulomb_law() -> void:
	var rules := StandardDuelRules.pit()
	var mu := rules.structure_pair(0, 0).friction
	var pairs: Array[ContactPair] = [rules.structure_pair(0, 0)]
	for slide: float in [40.0, 0.5]:
		var scene := _point_on_the_wall(rules, 0.2, 0.0, slide)
		var fighter: FighterState = scene[0]
		var contact: StructureContactSet = scene[1]
		var pose: BladePose = scene[2]
		var spec := rules.combatant(0)
		var inertia := ContactMechanics.weapon_inertia(pose, spec)
		var inverse := ContactMechanics.body_inverse_mass(spec)
		var before := StructureContactSolver.kinetic_energy(fighter, inertia, inverse)
		var tangent_before := -StructureContactSolver.closing_speed(fighter, pose, contact.point_x[0], contact.point_y[0], 0.0, -1.0)
		var delta := PackedFloat64Array([0.0])
		var rows := PackedFloat64Array([0.0])
		StructureContactSolver.solve(contact, fighter, pose, pairs, inertia, inverse, delta, rows, ContactLcp.new())
		var jn := contact.normal_impulse[0]
		var jt := contact.tangent_impulse[0]
		var tangent_after := -StructureContactSolver.closing_speed(fighter, pose, contact.point_x[0], contact.point_y[0], 0.0, -1.0)
		assert_true(jn > 0.0, "slide %.2f: the wall pushes" % slide)
		assert_true(absf(jt) <= mu * jn + 1e-12, "slide %.2f: |Jt| %.4f ≤ μ·Jn %.4f" % [slide, absf(jt), mu * jn])
		assert_true(absf(tangent_after) < absf(tangent_before), "slide %.2f: friction slows the slide (%.3f → %.3f)" % [slide, tangent_before, tangent_after])
		assert_true(tangent_after * signf(tangent_before) >= -1.0e-9, "slide %.2f: and never reverses it (%.12f)" % [slide, tangent_after])
		assert_true(StructureContactSolver.kinetic_energy(fighter, inertia, inverse) <= before + 1e-12, "slide %.2f: passive" % slide)
		if slide > 10.0:
			## The final normal top-up may widen the cone after the last tangent
			## step, so a saturated row sits at or just inside its bound.
			assert_true(absf(jt) >= 0.5 * mu * jn, "a fast slide spends the cone (|Jt| %.4f of μ·Jn %.4f)" % [absf(jt), mu * jn])
			assert_true(absf(tangent_after) > 0.1, "and keeps sliding (%.3f m/s)" % tangent_after)
		else:
			assert_true(absf(jt) < mu * jn, "a slow slide is held inside the cone")
			assert_near(tangent_after, 0.0, 1e-9, "and sticks")


## A cut swung into the east wall stops at the stone once, and stays out of
## it. No hit, no parry, no opponent contact. The same swing with no wall
## passes where the stone would be.
func test_a_cut_into_the_stone_stops_there_once() -> void:
	for speed: float in [20.0, 45.0]:
		var walled := _swing_at_wall(StandardDuelRules.pit(), speed)
		var runner: SimRunner = walled[0]
		var deepest: float = walled[1]
		var label := "%.0f rad/s" % speed
		var hits := DuelFixture.of_type(runner.events, DuelEventTypes.BLADE_STRUCTURE_CONTACT)
		assert_eq(hits.size(), 1, "%s: one structure contact" % label)
		if hits.size() == 1:
			assert_eq(int(hits[0].number(DuelEventKeys.STRUCTURE)), 0, "%s: on the stone wall" % label)
			assert_true(hits[0].number(DuelEventKeys.IMPULSE) > 0.0, "%s: with a real impulse" % label)
			assert_eq(hits[0].text(DuelEventKeys.MATERIAL_0), String(MaterialCatalog.STEEL), "%s: the blade's material rides the event" % label)
			assert_eq(hits[0].text(DuelEventKeys.MATERIAL_1), String(MaterialCatalog.STONE), "%s: and the wall's" % label)
		assert_true(deepest >= -2.0 * runner.rules.combat.contact_slop - SLOP_SLACK, "%s: the blade never ends a tick in the stone (deepest %.4f m)" % [label, deepest])
		assert_eq(runner.count(DuelEventTypes.BODY_HIT) + runner.count(DuelEventTypes.PARRY) + runner.count(DuelEventTypes.BLADE_CONTACT), 0, "%s: no hit, no parry, no clash" % label)
		assert_eq(runner.state.fighter(1).health, runner.rules.combatant(1).fighter.max_health, "%s: the opponent is untouched" % label)
		assert_false(runner.state.fighter(0).weapon.attack_contacted, "%s: and the wall is not the opponent" % label)
		assert_true(runner.state.fighter(0).impact_authority < 1.0, "%s: the stone jars the sword" % label)
		assert_true(runner.is_sound(), "%s: every tick is a legal state (%s)" % [label, runner.violation_summary()])
	var open := _swing_at_wall(StandardDuelRules.create(), 20.0)
	assert_eq((open[0] as SimRunner).count(DuelEventTypes.BLADE_STRUCTURE_CONTACT), 0, "with no wall there is nothing to meet")
	assert_true(float(open[1]) < -0.1, "and the blade passes where the stone would be (%.3f m)" % float(open[1]))
	var again := _swing_at_wall(StandardDuelRules.pit(), 20.0)
	var first := _swing_at_wall(StandardDuelRules.pit(), 20.0)
	assert_eq(StateHasher.hash_state((again[0] as SimRunner).state), StateHasher.hash_state((first[0] as SimRunner).state), "the same scene twice hashes the same")


## Held against the stone, the sword keeps one feature and one record: no
## second impact while it rests there.
func test_a_blade_held_on_the_wall_does_not_strike_again() -> void:
	var walled := _swing_at_wall(StandardDuelRules.pit(), 20.0, 120)
	var runner: SimRunner = walled[0]
	var features: Dictionary = walled[2]
	assert_eq(runner.count(DuelEventTypes.BLADE_STRUCTURE_CONTACT), 1, "one impact over two seconds")
	assert_true(int(walled[3]) > 0, "fixture: the sword was held on the stone for %d ticks" % int(walled[3]))
	assert_eq(features.size(), 1, "and kept one feature identity while held (%s)" % [features.keys()])


## The wall's policy is blade-only (STRUCTURE-CONTACT-001): the fighter's body
## is not caught by the scenery. Driven straight out into the east wall with the
## blade held inward, the body stops at the support circle (the edge policy's
## job, ArenaConstraints), short of the 8.27 m wall, emits no structure contact,
## and can still slide along the edge — it is never trapped against the stone.
func test_the_wall_blocks_the_blade_only_not_the_body() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(rules, 5)
	runner.skip_intro()
	var push := rules.combatant(0).fighter.push_radius
	## Duel-relative axes: (0, -1) retreats away from the opponent, straight out
	## toward the near wall; the neutral blade stays pointed inward.
	for _tick in 220:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, -1.0), PlayerCommand.idle(runner.state.tick))
	var a := runner.state.fighter(0)
	var reach := SimMath.length(a.x, a.y)
	assert_eq(runner.count(DuelEventTypes.BLADE_STRUCTURE_CONTACT), 0, "driving the body out never makes a wall contact")
	assert_true(runner.state.structure_contacts[0].hold_count == 0, "and no structure hold is left on the body")
	assert_true(reach <= rules.platform_radius - push + rules.combat.contact_slop, "the body stops at the support circle (%.3f m), short of the 8.27 m wall" % reach)
	assert_true(reach > rules.platform_radius - push - 0.3, "fixture: it actually reached the edge (%.3f m)" % reach)
	var bx := a.x
	var by := a.y
	for _tick in 30:
		runner.push(PlayerCommand.create(runner.state.tick, 1.0, 0.0), PlayerCommand.idle(runner.state.tick))
	var moved := SimMath.length(runner.state.fighter(0).x - bx, runner.state.fighter(0).y - by)
	assert_true(moved > 0.3, "and it can still slide along the edge, not trapped (%.3f m)" % moved)
	assert_true(runner.is_sound(), "every tick is legal (%s)" % runner.violation_summary())


## The guarantee the audit calls the critical distinction: a blade that cannot
## cross the wall must also come off it. Pressed on the stone, then the fighter
## pulls back toward the centre — the contact lifecycle releases within the
## retreat, leaves no stale hold, strikes the wall no further times, and the
## blade ends clear of it. "Did not tunnel" is not "did not get stuck".
func test_a_blade_pressed_on_the_wall_comes_off_when_the_fighter_pulls_away() -> void:
	var runner := _press_on_wall(StandardDuelRules.pit(), 20.0)
	var contact := runner.state.structure_contacts[0]
	assert_true(contact.is_persisted(), "fixture: the sword is pressed on the stone")
	var impacts := runner.count(DuelEventTypes.BLADE_STRUCTURE_CONTACT)
	var released := -1
	for tick in 40:
		runner.push(PlayerCommand.create(runner.state.tick, -1.0, 0.0), PlayerCommand.idle(runner.state.tick))
		if released < 0 and not contact.is_persisted():
			released = tick
	assert_true(released >= 0, "the contact releases as the fighter pulls away")
	assert_eq(contact.phase, StructureContactSet.Phase.SEPARATED, "back to separated, not a lingering hold (released at tick %d)" % released)
	assert_eq(contact.hold_count, 0, "no stale structure hold")
	assert_eq(runner.count(DuelEventTypes.BLADE_STRUCTURE_CONTACT), impacts, "a clean retreat strikes the wall no further times")
	var spec := runner.rules.combatant(0)
	var pose := WeaponKinematics.pose_of(runner.state.fighter(0), spec, BladePose.new())
	var tip := SimMath.length(pose.point_x(spec.weapon.tip_radius), pose.point_y(spec.weapon.tip_radius))
	assert_true(tip < 8.27 - spec.weapon.blade_radius, "and the blade ends clear of the wall (%.3f m from the centre)" % tip)
	assert_true(runner.is_sound(), "every tick is legal (%s)" % runner.violation_summary())


## The whole press-and-release is one deterministic path: the same scene twice,
## pressed and pulled away by the same commands, ends in the same authoritative
## state. A recovery that drifts between runs is a determinism defect.
func test_the_press_and_release_on_the_wall_is_replay_stable() -> void:
	var first := _press_on_wall(StandardDuelRules.pit(), 20.0)
	var second := _press_on_wall(StandardDuelRules.pit(), 20.0)
	for _tick in 40:
		first.push(PlayerCommand.create(first.state.tick, -1.0, 0.0), PlayerCommand.idle(first.state.tick))
		second.push(PlayerCommand.create(second.state.tick, -1.0, 0.0), PlayerCommand.idle(second.state.tick))
	assert_eq(StateHasher.hash_state(first.state), StateHasher.hash_state(second.state), "the same press and retreat hashes the same")
	assert_false(first.state.structure_contacts[0].is_persisted(), "and both end released")


## The north door is its own structure and material. A still sword carried
## into the recess by its wielder's body meets the wood, not the stone beside
## it: body-driven contact goes through the same rows as a cut.
func test_a_blade_carried_into_the_north_door_meets_wood() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(b, 2.5, 7.0, PI)
	var spec := rules.combatant(0)
	## The tip already in the opening, short of the door, the sword pointing up
	## the gate axis; then the body is carried north at 3 m/s.
	var start := Vector2.ZERO
	var at_y := 6.8
	for attempt in 60:
		var facing := SimMath.arctan2(b.y - at_y, b.x)
		ContactFixture.arm(a, 0.0, at_y, facing, SimMath.wrap_angle(deg_to_rad(92.0) - facing), 0.0, CombatPhase.Id.NEUTRAL, 0.0, spec.weapon)
		var opening := WeaponKinematics.pose_of(a, spec, BladePose.new())
		start = Vector2(opening.point_x(spec.weapon.tip_radius), opening.point_y(spec.weapon.tip_radius))
		if start.length() >= 8.40:
			break
		at_y += 0.01
	assert_true(absf(start.x) < StageStructures.GATE_HALF_WIDTH - 0.1 and start.length() > 8.3 and start.length() < StageStructures.DOOR_RADIUS - spec.weapon.blade_radius, "fixture: the tip starts in the opening short of the door (%.3f, %.3f), fighter at y %.2f" % [start.x, start.y, at_y])
	a.vy = 3.0
	DuelFixture.weapon_clear_of(b, a.x, a.y)
	var reach := 0.0
	var nearest := INF
	var geometry := StructureContactGeometry.new()
	var trace := PackedStringArray()
	for _tick in 40:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		var pose := WeaponKinematics.pose_of(a, spec, BladePose.new())
		var tx := pose.point_x(spec.weapon.tip_radius)
		var ty := pose.point_y(spec.weapon.tip_radius)
		reach = maxf(reach, SimMath.length(tx, ty))
		geometry.measure(pose.point_x(spec.weapon.blade_base_radius), pose.point_y(spec.weapon.blade_base_radius), tx, ty, spec.weapon.blade_radius, rules.structures, 0.0)
		nearest = minf(nearest, geometry.least_gap)
		if trace.size() < 12:
			trace.append("(%.2f,%.2f %s %.2f)" % [tx, ty, CombatPhase.Id.keys()[a.weapon.phase], a.weapon.speed])
	var hits := DuelFixture.of_type(runner.events, DuelEventTypes.BLADE_STRUCTURE_CONTACT)
	assert_true(reach > 8.4, "fixture: the tip reaches into the recess (%.3f m from the centre)" % reach)
	assert_true(hits.size() >= 1, "the cut meets the gate (nearest gap %.4f, reach %.3f, %s)" % [nearest, reach, " ".join(trace)])
	if hits.size() >= 1:
		assert_eq(int(hits[0].number(DuelEventKeys.STRUCTURE)), 1, "the north gate, not the stone beside it")
	assert_true(runner.is_sound(), "every tick is legal (%s)" % runner.violation_summary())


## With one new contact allowed per tick the loop saturates, and the blade
## still does not pass through the stone: the position stage holds it.
func test_a_saturated_tick_does_not_let_the_blade_through() -> void:
	var rules := StandardDuelRules.pit()
	rules.combat.max_contacts_per_tick = 1
	var walled := _swing_at_wall(rules, 45.0)
	var deepest: float = walled[1]
	assert_true(deepest >= -2.0 * rules.combat.contact_slop - SLOP_SLACK, "the blade stays out of the stone (deepest %.4f m)" % deepest)
	assert_true((walled[0] as SimRunner).is_sound(), "and every tick is legal")


## Fighter 0 at (7.5, 0), its sword pointing at the east wall with the tip on
## the stone, its body moving at `into` m/s toward the wall and `along` m/s
## along it, its sword turning at `turning` rad/s. One recorded contact point
## at the tip.
func _point_on_the_wall(rules: DuelRules, into: float, along: float, turning: float) -> Array:
	var state := DuelSetup.new_state(rules, 1)
	var fighter := state.fighter(0)
	DuelFixture.place(fighter, 7.5, 0.0, 0.0)
	fighter.weapon.angle = 0.0
	fighter.weapon.speed = turning
	fighter.vx = into
	fighter.vy = along
	var spec := rules.combatant(0)
	var pose := WeaponKinematics.pose_of(fighter, spec, BladePose.new())
	var contact := state.structure_contacts[0]
	contact.record_point(0, StructureContactSet.feature_of(0, 1), pose.point_x(spec.weapon.tip_radius), pose.point_y(spec.weapon.tip_radius), -1.0, 0.0, 0.0, 1.0)
	contact.point_count = 1
	return [fighter, contact, pose]


## A fighter sandwiched between the opponent's body and the Arena wall is not
## shoved through the stone: the body is bounded by the edge policy (the support
## circle), never by the blade-only structure, so no amount of pushing drives it
## past the wall. And the pin is not a trap - once the opponent backs off the
## pinned fighter moves freely again, with no stale hold, every tick legal.
func test_a_fighter_pinned_on_the_wall_by_the_opponent_is_not_pushed_through() -> void:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(rules, 7)
	runner.skip_intro()
	var push0 := rules.combatant(0).fighter.push_radius
	var push1 := rules.combatant(1).fighter.push_radius
	var edge := rules.platform_radius - push0
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	## Fighter 0 at the east edge facing the opponent; fighter 1 just inside it,
	## bodies barely overlapping, facing out toward the wall.
	DuelFixture.place(a, edge - 0.05, 0.0, PI)
	DuelFixture.place(b, edge - 0.05 - (push0 + push1) + 0.02, 0.0, 0.0)
	## Fighter 1 drives into fighter 0 (closes); fighter 0 is pinned on the wall.
	var max_reach := 0.0
	for _tick in 50:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.create(runner.state.tick, 0.0, 1.0))
		max_reach = maxf(max_reach, SimMath.length(a.x, a.y))
		assert_true(runner.is_sound(), "pinned, every tick is legal (%s)" % runner.violation_summary())
	assert_true(max_reach > edge - 0.3, "fixture: the body was driven onto the edge (%.3f m)" % max_reach)
	assert_true(max_reach <= edge + rules.combat.contact_slop + 1.0e-3, "the opponent cannot shove the body through the wall (%.3f m, edge %.3f, wall %.3f)" % [max_reach, edge, rules.platform_radius])
	## The opponent backs off and the pinned fighter steps along the edge: it was
	## held by physics, not trapped.
	for _tick in 30:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.create(runner.state.tick, 0.0, -1.0))
	var bx := a.x
	var by := a.y
	for _tick in 20:
		runner.push(PlayerCommand.create(runner.state.tick, 1.0, 0.0), PlayerCommand.idle(runner.state.tick))
	assert_true(SimMath.length(a.x - bx, a.y - by) > 0.3, "once the opponent backs off the pinned fighter moves freely")
	assert_eq(runner.state.structure_contacts[0].hold_count, 0, "no stale wall hold on the pinned fighter")
	assert_eq(runner.state.blade_contact.hold_count() + runner.state.blade_contact.point_count, 0, "and no blade stays locked")
	assert_true(runner.is_sound(), "every tick of the disengage is legal (%s)" % runner.violation_summary())


## The whole pin-and-disengage is one deterministic path.
func test_the_wall_pin_and_disengage_is_replay_stable() -> void:
	assert_eq(StateHasher.hash_state(_pin_sequence().state), StateHasher.hash_state(_pin_sequence().state), "the same pin and disengage hashes the same")


## Fighter 1 pins fighter 0 on the east wall, then backs off while fighter 0
## steps along the edge - a fixed deterministic sequence for the replay check.
func _pin_sequence() -> SimRunner:
	var rules := StandardDuelRules.pit()
	var runner := SimRunner.create(rules, 7)
	runner.skip_intro()
	var push0 := rules.combatant(0).fighter.push_radius
	var push1 := rules.combatant(1).fighter.push_radius
	var edge := rules.platform_radius - push0
	DuelFixture.place(runner.state.fighter(0), edge - 0.05, 0.0, PI)
	DuelFixture.place(runner.state.fighter(1), edge - 0.05 - (push0 + push1) + 0.02, 0.0, 0.0)
	for _tick in 50:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.create(runner.state.tick, 0.0, 1.0))
	for _tick in 30:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.create(runner.state.tick, 0.0, -1.0))
	for _tick in 20:
		runner.push(PlayerCommand.create(runner.state.tick, 1.0, 0.0), PlayerCommand.idle(runner.state.tick))
	return runner


## Fighter 0 cuts into the east wall and is stepped forward until its blade is
## genuinely persisted on the stone (the release tests start from a real hold,
## not a single-tick graze). The opponent stands clear to the south-west.
func _press_on_wall(rules: DuelRules, speed: float) -> SimRunner:
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(b, 6.8, -2.5, 0.0)
	var facing := SimMath.arctan2(b.y - 0.0, b.x - 7.5)
	b.facing = SimMath.arctan2(-b.y, 7.5 - b.x)
	ContactFixture.arm(a, 7.5, 0.0, facing, SimMath.wrap_angle(deg_to_rad(-128.5) - facing), speed, CombatPhase.Id.ACTIVE_THREAT, 1.0, rules.combatant(0).weapon)
	DuelFixture.weapon_clear_of(b, a.x, a.y)
	for _tick in 40:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		if runner.state.structure_contacts[0].is_persisted():
			break
	return runner


## Fighter 0 at (7.5, 0) facing its opponent to the south-west, its cut swung
## counter-clockwise at `speed` from inside the arena toward the east wall.
## Returns the runner, the deepest end-of-tick gap of its blade to the wall's
## arcs, the features it was held on, and how many ticks it was held.
func _swing_at_wall(rules: DuelRules, speed: float, ticks: int = 40) -> Array:
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(b, 6.8, -2.5, 0.0)
	var facing := SimMath.arctan2(b.y - 0.0, b.x - 7.5)
	b.facing = SimMath.arctan2(-b.y, 7.5 - b.x)
	ContactFixture.arm(a, 7.5, 0.0, facing, SimMath.wrap_angle(deg_to_rad(-128.5) - facing), speed, CombatPhase.Id.ACTIVE_THREAT, 1.0, rules.combatant(0).weapon)
	DuelFixture.weapon_clear_of(b, a.x, a.y)
	var walls := StandardDuelRules.pit().structures
	var geometry := StructureContactGeometry.new()
	var spec := rules.combatant(0)
	var deepest := INF
	var features := {}
	var held := 0
	for _tick in ticks:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		var pose := WeaponKinematics.pose_of(a, spec, BladePose.new())
		geometry.measure(pose.point_x(spec.weapon.blade_base_radius), pose.point_y(spec.weapon.blade_base_radius), pose.point_x(spec.weapon.tip_radius), pose.point_y(spec.weapon.tip_radius), spec.weapon.blade_radius, walls, 0.0)
		deepest = minf(deepest, geometry.least_gap)
		if not runner.state.structure_contacts.is_empty():
			var contact := runner.state.structure_contacts[0]
			if contact.hold_count > 0:
				held += 1
				features[contact.hold_feature[0]] = true
	return [runner, deepest, features, held]
