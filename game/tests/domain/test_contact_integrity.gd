extends TestCase

## CONTACT-INTEGRITY: swords and living bodies stay rigid for as long as a
## contact lasts, not only at the time of impact (RIGID-CONTACT-001). A first
## clash being resolved correctly says nothing about the ticks after it: a
## blade still driven by its motor, or a fighter still walking into a held
## sword, must not be able to push through what it rests on.
##
## The corpus case is the duel itself — seeded pilots, the real tick, every
## live tick measured — so it holds the property the game ships with, not a
## hand-built scene. The constructed cases pin the mechanisms the corpus
## relies on: motor pressure, a blocking sword, and mirror symmetry.
##
## See also: /docs/reference/testing.md
## See also: /docs/concepts/combat.md

## The development corpus the passivity audit plays (CONTACT-INTEGRITY-SHIP
## plays it, and the ship corpus, for rigidity).
const SEEDS := ContactGauge.DEVELOPMENT_SEEDS
const DUEL_TICKS := ContactGauge.DUEL_TICKS
const NUMERICAL_TOLERANCE := ContactGauge.NUMERICAL_TOLERANCE
## Ticks a pressure scenario is held for.
const PRESSURE_TICKS := 45
## How deep the crossed guards of `_overlapping_guards` overlap (m).
const CROSSED_OVERLAP := 0.01
## How far apart the guards of the walk-in scene start (m).
const WALK_IN_GAP := 0.08
## The re-hold storm (CONTACT-FALLBACK-001), found by searching adversarial
## point-symmetric states: separation (m), heading off the line (rad), each
## body's closing and lateral speed (m/s), heading spin (rad/s), sword angle
## (rad) and swing (rad/s), and how long it is followed (ticks). Re-searched
## on rules 50 (blade-only steel): the rules-49 storm spent its budget on the
## crossguards and handles, and its blades no longer meet. Rules 55: 1.43 m
## enters both torsos before the blades can re-hold four times. 1.60 m still
## spends the budget. Torso hits may happen; the assertions are the fallback.
const STORM_DISTANCE := 1.60
const STORM_FACING := 0.559
const STORM_CLOSING := 3.21
const STORM_LATERAL := -0.15
const STORM_TURN := -1.3
const STORM_ANGLE := -0.948
const STORM_SWING := -7.5
const STORM_TICKS := 8

var _rules: DuelRules


func _init() -> void:
	suite_name = "CONTACT-INTEGRITY"
	_rules = DuelFixture.rules()


func _blades(state: MatchState) -> Vector2:
	return ContactGauge.blades(_rules, state)


func _centrelines(state: MatchState) -> float:
	return ContactGauge.centrelines(_rules, state)


func _body(wielder: FighterState, target: FighterState) -> float:
	return ContactGauge.body(_rules, wielder, target)


func _allowed() -> float:
	return ContactGauge.allowed(_rules)


## A fighter holding a diagonal guard walks it into the opponent's opposite
## diagonal guard — the blades cross in an X — and keeps walking. `side`
## mirrors the whole scene (+1 / −1); without `guard` the opponent's blade is
## wound back out of the way. Returns [runner, side of blade 1 at the start,
## worst overlap, ticks touching, gap at the start].
func _walk_into_guard(side: float, guard: bool) -> Array:
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	var state := runner.state
	## Laid along the y axis, so the mirror is x → −x and neither heading wraps
	## across ±π: both scenes hold bit-identical headings.
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, side * deg_to_rad(45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var held := side * deg_to_rad(-45.0 if guard else 135.0)
	ContactFixture.arm(state.fighter(1), 0.0, ContactFixture.crossed_guard_separation(spec, WALK_IN_GAP, side), -PI / 2.0, held, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	## A resting blade's swing direction is state too: each would cut toward
	## its other side, so the mirrored scene mirrors it as well.
	for fighter in state.fighters:
		fighter.weapon.swing_dir = -signf(fighter.weapon.angle)
	var start := _blades(state)
	var worst := 0.0
	var touching := 0
	var blades_touching := 0
	for _tick in PRESSURE_TICKS:
		runner.push(PlayerCommand.create(state.tick, 0.0, 1.0), PlayerCommand.idle(state.tick))
		var now := _blades(state)
		worst = maxf(worst, -now.x)
		if now.x <= 0.0:
			touching += 1
		if _centrelines(state) <= 2.0 * weapon.blade_radius:
			blades_touching += 1
	return [runner, start.y, worst, touching, start.x, blades_touching]


func test_walking_pressure_never_drives_a_blade_through_a_held_blade() -> void:
	## Control: with the opponent's blade wound out of the way, the same walk
	## never meets that blade and carries the fighter on through, far past
	## where the held guard stops it. (The wound sword's hilt still rides in
	## front of its wielder, SLASH-SHAPE-001, so the hilts may meet up close.)
	var open := _walk_into_guard(-1.0, false)
	var open_runner: SimRunner = open[0]
	var held := _walk_into_guard(-1.0, true)
	var runner: SimRunner = held[0]
	assert_eq(int(open[5]), 0, "control: the blades never meet")
	assert_true(open_runner.state.fighter(0).y > 1.5, "control: the walk advances a long way (%.2f m)" % open_runner.state.fighter(0).y)
	assert_true(float(held[4]) > 0.05, "fixture: the guards start apart (%.3f m)" % float(held[4]))
	assert_true(int(held[3]) > 20, "fixture: the blades are pressed together for most of the walk (%d ticks)" % int(held[3]))
	assert_true(float(held[2]) <= _allowed(), "the pressed blades never overlap beyond the slop (worst %.4f m)" % float(held[2]))
	assert_eq(_blades(runner.state).y, float(held[1]), "and the point is still on the side it met the blade from")


## Torso hits among `runner`'s events — the body behind a blocking sword. A
## cut that slides along the blocking blade is not a torso hit scored through
## that blade (TORSO-CIRCLE-001).
static func _torso_hits(runner: SimRunner) -> int:
	var hits := 0
	for event in runner.events:
		if event.type == DuelEventTypes.BODY_HIT and event.text(DuelEventKeys.REGION) == DuelEventKeys.REGION_TORSO:
			hits += 1
	return hits


func test_motor_pressure_never_drives_a_cut_through_a_blocking_sword() -> void:
	## A driven cut meets a sword held between it and the body, and its motor
	## keeps driving. Defence first in time is defence for as long as it holds.
	var open: SimRunner = _pressed_cut(deg_to_rad(-135.0))[0]
	assert_eq(open.count(DuelEventTypes.BLADE_CONTACT), 0, "control: with the guard wound back nothing meets the cut")
	assert_eq(_torso_hits(open), 1, "control: and the cut lands on the body")
	var blocked := _pressed_cut(deg_to_rad(50.0))
	var runner: SimRunner = blocked[0]
	assert_true(float(blocked[2]) > 0.05, "fixture: the cut starts clear of the guard (%.3f m)" % float(blocked[2]))
	assert_true(runner.count(DuelEventTypes.BLADE_CONTACT) >= 1, "fixture: the guard is met")
	assert_eq(_torso_hits(runner), 0, "and the cut never reaches the body behind it")
	assert_true(float(blocked[1]) <= _allowed(), "nor sinks into the guard beyond the slop (worst %.4f m)" % float(blocked[1]))


## A driven cut from −110° into a defender 1.45 m away whose sword waits at
## `guard`, run for the pressure window. Returns [runner, worst blade overlap,
## gap at the start].
func _pressed_cut(guard: float, inert: bool = false) -> Array:
	var runner := SimRunner.create(_rules, 5)
	if inert:
		runner.simulation.rigid_solver = InertRigidSolver.new()
	runner.skip_intro()
	var state := runner.state
	var weapon := _rules.combatant(0).weapon
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, deg_to_rad(-110.0), 6.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	ContactFixture.arm(state.fighter(1), 1.45, 0.0, PI, guard, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	var start := _blades(state).x
	var worst := 0.0
	for _tick in PRESSURE_TICKS:
		runner.idle(1)
		worst = maxf(worst, -_blades(state).x)
	return [runner, worst, start]


## Two diagonal guards crossed in an X and overlapping by about a centimetre,
## held (`CONTACTING`) unless `pending` — a touch the sweep has not resolved
## as a contact yet.
func _overlapping_guards(pending: bool = false) -> MatchState:
	var state := DuelFixture.state(_rules)
	var weapon := _rules.combatant(0).weapon
	var spec := _rules.combatant(0)
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, deg_to_rad(45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(state.fighter(1), 0.0, ContactFixture.crossed_guard_separation(spec, -CROSSED_OVERLAP), -PI / 2.0, deg_to_rad(-45.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	if not pending:
		state.blade_contact.set_phase(SwordContactSet.Phase.CONTACTING)
	return state


func test_the_position_stage_clears_overlap_without_adding_motion() -> void:
	var state := _overlapping_guards()
	var a := state.fighter(0)
	var b := state.fighter(1)
	a.vy = 0.8
	b.vx = -0.3
	a.weapon.speed = 1.5
	var before := _blades(state)
	assert_between(before.x, -0.02, -0.005, "fixture: the held blades overlap by about a centimetre (%.4f m)" % before.x)
	RigidContactSolver.new().project(state, _rules)
	var after := _blades(state)
	assert_near(after.x, -_rules.combat.contact_slop, NUMERICAL_TOLERANCE, "the overlap is pushed back to the slop")
	assert_eq(after.y, before.y, "the blades stay on the sides they touch from")
	## Position correction moves the swords, never their speeds: nothing it
	## does can add kinetic energy.
	assert_eq(a.vy, 0.8, "slot 0's body speed is untouched")
	assert_eq(b.vx, -0.3, "slot 1's body speed is untouched")
	assert_eq(a.weapon.speed, 1.5, "slot 0's sword speed is untouched")
	assert_eq(b.weapon.speed, 0.0, "slot 1's sword speed is untouched")
	## Perturb: the same overlap before the sweep has resolved it as a contact
	## is a pending hit, and the constraint leaves it alone.
	var pending := _overlapping_guards(true)
	RigidContactSolver.new().project(pending, _rules)
	assert_eq(_blades(pending).x, before.x, "an unresolved touch is the sweep's, not the constraint's")


func test_the_velocity_stage_stops_closing_and_never_pulls() -> void:
	var closing := _overlapping_guards()
	closing.fighter(0).vy = 1.2
	var solver := RigidContactSolver.new()
	var stopped := solver.solve_velocity(closing, _rules)
	assert_true(stopped > 0.0, "a fighter walking into a held blade is stopped by an impulse (%.3f N·s)" % stopped)
	assert_true(closing.fighter(0).vy < 1.2, "and slowed by it")
	var left := solver.solve_velocity(closing, _rules)
	assert_true(left <= 1.0e-4 * stopped, "nothing is left closing afterwards (%s N·s)" % str(left))
	## Perturb: walking away from the same held blade.
	var parting := _overlapping_guards()
	parting.fighter(0).vy = -1.2
	assert_eq(solver.solve_velocity(parting, _rules), 0.0, "a contact that is separating takes no impulse")
	assert_eq(parting.fighter(0).vy, -1.2, "so the constraint never pulls")
	assert_eq(parting.fighter(1).vy, 0.0, "on either side")


## The persistent constraint over real play — held blades, swords on torsos,
## swords pinned between both — with the actuators frozen while it solves.
func test_held_contacts_are_passive_and_conserve_momentum() -> void:
	var velocity_solves := 0
	var position_solves := 0
	var energy_gain := -INF
	var momentum := 0.0
	var touched := 0.0
	var velocity_body_rows := 0
	var position_body_rows := 0
	var stop_solves := 0
	var stop_overrun := -INF
	for seed_value: int in SEEDS:
		var runner := SimRunner.create(_rules, seed_value)
		var audit := AuditedRigidSolver.new()
		audit.diagnostics = runner.simulation.diagnostics
		runner.simulation.rigid_solver = audit
		runner.run(Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23), DUEL_TICKS)
		velocity_solves += audit.velocity_solves
		position_solves += audit.position_solves
		energy_gain = maxf(energy_gain, audit.worst_energy_gain)
		momentum = maxf(momentum, audit.worst_momentum_change)
		touched = maxf(touched, audit.worst_velocity_touch)
		velocity_body_rows += audit.velocity_body_rows
		position_body_rows += audit.position_body_rows
		stop_solves += audit.stop_solves
		stop_overrun = maxf(stop_overrun, audit.worst_stop_overrun)
	assert_true(stop_solves > 20, "fixture: held swords near their guard stops are solved often (%d)" % stop_solves)
	## The block is regularized (1e-6 on the diagonal) and the last tangent
	## clamp follows the last normal solve, so the bound holds to ~1e-5 rad/s —
	## well under a micrometre of tip travel a tick.
	assert_true(stop_overrun <= 1.0e-4, "a held solve never sets a sword to turn past its stop within the tick (worst %s rad/s)" % str(stop_overrun))
	assert_true(velocity_solves > 200, "fixture: held contacts were solved often (%d velocity solves)" % velocity_solves)
	assert_true(position_solves > 20, "fixture: and overlap was corrected often (%d position solves)" % position_solves)
	assert_true(energy_gain <= 1.0e-9, "a held contact never adds kinetic energy (worst %s J)" % str(energy_gain))
	assert_true(momentum <= 1.0e-9, "linear momentum is conserved by every hold (worst %s N·s)" % str(momentum))
	assert_eq(touched, 0.0, "overlap correction never touches a velocity, so it moves no energy or momentum")
	## BODY-CONTACT-OWNERSHIP-001: one owner of body/body velocity response.
	assert_eq(velocity_body_rows, 0, "the bodies never take a velocity impulse from the sword solver (ContactResolver owns it)")
	assert_true(position_body_rows > 0, "while the position stage still keeps them apart as it clears a sword (%d solves)" % position_body_rows)


## A first impact happens before anything is held, so the persistent
## constraint must leave it exactly as the impulse model resolves it.
func test_a_clean_first_impact_is_untouched_by_the_constraint() -> void:
	var real_cut: SimRunner = _pressed_cut(deg_to_rad(-135.0))[0]
	var inert_cut: SimRunner = _pressed_cut(deg_to_rad(-135.0), true)[0]
	var real_hit := real_cut.first(DuelEventTypes.BODY_HIT)
	var inert_hit := inert_cut.first(DuelEventTypes.BODY_HIT)
	assert_true(real_hit != null and inert_hit != null, "fixture: the unobstructed cut lands either way")
	assert_eq(real_cut.count(DuelEventTypes.BLADE_CONTACT), 0, "fixture: nothing was held before it")
	if real_hit == null or inert_hit == null:
		return
	assert_eq(real_hit.tick, inert_hit.tick, "the cut lands on the same tick")
	assert_eq(real_hit.data, inert_hit.data, "with the same point, closing speed, impulse, energy and damage")
	var real_clash := _first_clash(false)
	var inert_clash := _first_clash(true)
	assert_true(real_clash != null and inert_clash != null, "fixture: the head-on cuts clash either way")
	if real_clash == null or inert_clash == null:
		return
	assert_eq(real_clash.tick, inert_clash.tick, "the clash happens on the same tick")
	assert_eq(real_clash.data, inert_clash.data, "with the same impulse, energy, fractions and normal")


## Two full slashes meeting head-on through the centre (the COLLIDE scene).
func _first_clash(inert: bool) -> DuelEvent:
	var runner := SimRunner.create(_rules, 1)
	if inert:
		runner.simulation.rigid_solver = InertRigidSolver.new()
	runner.skip_intro()
	for slot in 2:
		ContactFixture.arm(runner.state.fighter(slot), 2.4 * slot, 0.0, PI * slot, deg_to_rad(-70.0), 14.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	for _tick in 30:
		runner.idle(1)
		var clash := runner.first(DuelEventTypes.BLADE_CONTACT)
		if clash != null:
			return clash
	return null


func test_the_solver_carries_nothing_between_solves() -> void:
	## Deterministic order: the same state solves the same way whatever the
	## solver did before — no row, impulse or mass leaks from one call into the
	## next.
	var reused := RigidContactSolver.new()
	var warmed := _overlapping_guards()
	warmed.fighter(1).vy = -0.9
	reused.solve_velocity(warmed, _rules)
	reused.project(warmed, _rules)
	var first := _overlapping_guards()
	first.fighter(0).vy = 1.2
	var second := _overlapping_guards()
	second.fighter(0).vy = 1.2
	reused.solve_velocity(first, _rules)
	reused.project(first, _rules)
	var fresh := RigidContactSolver.new()
	fresh.solve_velocity(second, _rules)
	fresh.project(second, _rules)
	for slot in 2:
		var a := first.fighter(slot)
		var b := second.fighter(slot)
		assert_eq([a.x, a.y, a.vx, a.vy, a.weapon.angle, a.weapon.speed], [b.x, b.y, b.vx, b.vy, b.weapon.angle, b.weapon.speed], "slot %d: a reused solver and a fresh one agree bit for bit" % slot)
	assert_eq(reused.weapon_delta, fresh.weapon_delta, "and report the same held-sword change")


## The constraint stops what the motors drive, and the motors' authority is
## bounded — they move a speed toward a target by at most force/mass (or
## torque/inertia) × dt per tick, never set it. So a blade the constraint
## stopped is pressed again next tick only by one tick of drive.
func test_the_motors_that_press_a_held_contact_are_bounded() -> void:
	var dt := SimulationTimebase.TICK_SECONDS
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var weapon := _rules.combatant(0).weapon
	var swordsman := runner.state.fighter(0)
	ContactFixture.arm(swordsman, 0.0, 0.0, 0.0, deg_to_rad(-60.0), 0.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	ContactFixture.arm(runner.state.fighter(1), 0.0, 6.0, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	swordsman.weapon.swing_dir = 1.0
	var ceiling := weapon.achievable_swing_speed(1.0, swordsman.weapon.launch_preparation)
	runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	var one_tick := weapon.swing_accel(1.0, _rules.combatant(0).fighter.weapon_torque_scale, WeaponKinematics.motor_inertia(_rules.combatant(0), deg_to_rad(-60.0))) * dt
	assert_true(ceiling > 2.0 * one_tick, "fixture: the swing's target speed is several ticks of drive away")
	assert_true(swordsman.weapon.speed > 0.0, "a stopped swing's motor drives it again")
	assert_true(swordsman.weapon.speed <= one_tick + 1.0e-9, "by at most one tick of torque over inertia (%.3f of %.3f rad/s)" % [swordsman.weapon.speed, one_tick])
	var walker := runner.state.fighter(1)
	walker.vx = 0.0
	walker.vy = 0.0
	runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.create(runner.state.tick, 0.0, 1.0))
	var step := _rules.combatant(0).fighter.move_accel() * dt
	assert_true(_rules.combatant(0).fighter.max_speed > 2.0 * step, "fixture: walking speed is several ticks of acceleration away")
	assert_true(walker.speed() > 0.0, "a stopped fighter's footwork drives them again")
	assert_true(walker.speed() <= step + 1.0e-9, "by at most one tick of force over mass (%.3f of %.3f m/s)" % [walker.speed(), step])


## The swing-interrupt law is a lifecycle rule, not a force: it changes what
## the weapon is doing, never how anything is moving.
func test_interrupting_a_held_swing_moves_nothing() -> void:
	var state := DuelFixture.state(_rules)
	var weapon := _rules.combatant(0).weapon
	var swordsman := state.fighter(0)
	ContactFixture.arm(swordsman, 0.0, 0.0, 0.0, deg_to_rad(-30.0), -0.5, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	ContactFixture.arm(state.fighter(1), 2.0, 0.0, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	swordsman.weapon.swing_dir = 1.0
	swordsman.vx = 0.4
	assert_true(swordsman.weapon.speed * swordsman.weapon.swing_dir < 0.0, "fixture: the hold has reversed the swing")
	ContactResolver.interrupt_held_swings(state, _rules, PackedFloat64Array([-3.0, 0.0]), PackedByteArray([1, 0]))
	assert_eq(swordsman.weapon.phase, CombatPhase.Id.RECOVERY, "the swing ends in recovery, as after a clash")
	assert_eq(swordsman.weapon.speed, -0.5, "the sword's speed is untouched")
	assert_eq(swordsman.vx, 0.4, "and so is the body's")
	## Perturb: a swing the hold slowed but left faster than control keeps going.
	var slowed := DuelFixture.state(_rules)
	ContactFixture.arm(slowed.fighter(0), 0.0, 0.0, 0.0, deg_to_rad(-30.0), weapon.control_speed + 0.5, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	ContactFixture.arm(slowed.fighter(1), 2.0, 0.0, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactResolver.interrupt_held_swings(slowed, _rules, PackedFloat64Array([-3.0, 0.0]), PackedByteArray([1, 0]))
	assert_eq(slowed.fighter(0).weapon.phase, CombatPhase.Id.ACTIVE_THREAT, "a swing still travelling its own way is not interrupted")


## Only a hold that arrested the cut ends it — brought it under control,
## stopped or reversed it.
func test_only_a_hold_that_arrests_a_cut_interrupts_it() -> void:
	var weapon := _rules.combatant(0).weapon
	var cases := [
		## [θ̇ after the hold, the hold's change to θ̇, phase after, why]
		[0.0, -3.0, CombatPhase.Id.RECOVERY, "a hold that stopped the cut ends it"],
		[0.2, -3.0, CombatPhase.Id.RECOVERY, "a hold that left it creeping under control ends it: a press, not a cut"],
		[2.0, -3.0, CombatPhase.Id.ACTIVE_THREAT, "a hold that left it travelling faster than control does not"],
		[1.0, 0.3, CombatPhase.Id.ACTIVE_THREAT, "a hold that pushed the sword along its cut never ends it"],
		[-0.5, -1.5, CombatPhase.Id.RECOVERY, "a hold that reversed the cut ends it"],
	]
	for case: Array in cases:
		var state := DuelFixture.state(_rules)
		var swordsman := state.fighter(0)
		ContactFixture.arm(swordsman, 0.0, 0.0, 0.0, deg_to_rad(-30.0), float(case[0]), CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
		ContactFixture.arm(state.fighter(1), 2.0, 0.0, PI, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
		swordsman.weapon.swing_dir = 1.0
		swordsman.weapon.launch_preparation = 1.0
		ContactResolver.interrupt_held_swings(state, _rules, PackedFloat64Array([float(case[1]), 0.0]), PackedByteArray([1, 0]))
		assert_eq(swordsman.weapon.phase, int(case[2]), String(case[3]))
		assert_eq(swordsman.weapon.speed, float(case[0]), "and the interrupt moves nothing either way")


## A driven cut from −110° into a defender `distance` away whose sword waits at
## `guard`. Records, per tick: blade clashes so far, manifold phase, the cut's
## phase, θ, θ̇, the defender's θ, the defender's θ̇, where the contact lies on
## the defender's blade, and body hits so far. The distances were found by a
## scan; what each scene *is* is asserted by its own preconditions, so a
## geometry change fails the fixture, not the law.
func _traced_cut(distance: float, guard: float, ticks: int) -> Array:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var state := runner.state
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, deg_to_rad(-110.0), 6.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, _rules.combatant(0).weapon)
	ContactFixture.arm(state.fighter(1), distance, 0.0, PI, guard, 0.0, CombatPhase.Id.NEUTRAL, 0.0, _rules.combatant(0).weapon)
	var rows: Array = []
	for _tick in ticks:
		runner.idle(1)
		var a := state.fighter(0)
		var d := state.fighter(1)
		rows.append([
			runner.count(DuelEventTypes.BLADE_CONTACT), state.blade_contact.phase, a.weapon.phase, a.weapon.angle, a.weapon.speed,
			d.weapon.angle, d.weapon.speed, state.blade_contact.fraction_b[0], runner.count(DuelEventTypes.BODY_HIT),
		])
	return [runner, rows]


## BLOCKED CUT: a cut that meets a guard lying across its path is reversed by
## the impact itself and ends there — the first-impact branch of the one law,
## through the real tick loop. Every tick before the clash the cut was live; on
## the clash tick it no longer progresses, so it is in recovery. (At μ = 0 a
## *held* blade rarely stops a cut — it slides; the held branch is pinned by
## the law table above and the hold's own scenes below.)
func test_a_contact_that_reverses_a_cut_ends_it() -> void:
	## Searched on rules 50 (the middle of a band from 1.9 to 2.2 m): the
	## rules-49 scene (2.0 m, −75°) reversed the cut on the defender's handle,
	## which is grip now — the cut wounds it on the way to the blade.
	var traced := _traced_cut(2.1, deg_to_rad(30.0), 16)
	var runner: SimRunner = traced[0]
	var rows: Array = traced[1]
	var clash := runner.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(clash != null, "fixture: the cut meets the guard")
	if clash == null:
		return
	assert_true(clash.number(DuelEventKeys.IMPULSE) > 0.1 * _rules.combat.reference_impulse, "fixture: a real impact, not a graze (%.2f N·s)" % clash.number(DuelEventKeys.IMPULSE))
	assert_true(clash.number(DuelEventKeys.CLOSING_SPEED) >= _rules.combatant(0).weapon.restitution_threshold_speed, "fixture: fast enough to rebound (%.2f m/s)" % clash.number(DuelEventKeys.CLOSING_SPEED))
	var at := -1
	for i in rows.size():
		if int(rows[i][0]) > 0:
			at = i
			break
	assert_true(at > 0, "fixture: the clash is inside the window, after the cut was underway")
	if at <= 0:
		return
	for i in at:
		assert_true(CombatPhase.is_swinging(int(rows[i][2])), "fixture tick %d: the cut is live before the clash" % i)
	assert_eq(int(rows[at][8]), 0, "fixture: no body hit came first")
	assert_true(bool(clash.data[DuelEventKeys.ARRESTED_0]), "the clash is reported as arresting the cut")
	assert_true(float(rows[at][4]) <= 0.0, "the impact reversed it (%.2f → %.2f rad/s)" % [float(rows[at - 1][4]), float(rows[at][4])])
	assert_eq(int(rows[at][2]), CombatPhase.Id.RECOVERY, "so the cut ends there, in recovery")


## PRESSURE-GUARD-001. A cut that beats a blade onto its stop and keeps
## pressing. This is not a glance: once the guard is against its stop the
## contact is two bodies behind a normal constraint. While the cut still
## travels faster than the wielder's `control_speed` the arrest law leaves it
## a cut — no ratio of its ceiling ends it. Once the press has brought it under
## control the cut is over: it ends in recovery, never pressed forever
## (RIGID-CONTACT-002). μ = 0 glancing is
## `test_a_frictionless_crossing_does_not_consume_tangent_velocity`.
func test_pressure_against_a_stopped_guard_stays_a_cut_while_it_progresses() -> void:
	var weapon := _rules.combatant(0).weapon
	## Slower than this a ratio law (v30's 40 % deflect fraction) would have
	## ended the cut; the physical law does not.
	var keep := 0.4 * weapon.achievable_swing_speed(1.0, 1.0)
	var traced := _traced_cut(1.5, deg_to_rad(45.0), 40)
	var runner: SimRunner = traced[0]
	var rows: Array = traced[1]
	assert_eq(runner.count(DuelEventTypes.BLADE_CONTACT), 1, "fixture: one clash, then only the hold")
	assert_eq(_torso_hits(runner), 0, "fixture: the cut never reaches the body (sliding into the grip is a grip graze)")
	var stopped := -1
	for i in range(1, rows.size()):
		if float(rows[i][6]) < 0.5 * float(rows[i - 1][6]) and float(rows[i - 1][6]) > 1.0:
			stopped = i
			break
	assert_true(stopped > 0, "fixture: the beaten guard does reach its stop inside the window")
	if stopped <= 0:
		return
	assert_true(absf(float(rows[stopped][5])) > weapon.guard_limit - deg_to_rad(10.0), "fixture: and that is its stop (%.1f°)" % rad_to_deg(float(rows[stopped][5])))
	var travelling := 0
	var slow := 0
	var slid_before := 0.0
	var ended := -1
	for i in range(1, rows.size()):
		var row: Array = rows[i]
		if not CombatPhase.is_swinging(int(row[2])):
			ended = i
			break
		assert_ne(int(row[1]), SwordContactSet.Phase.SEPARATED, "fixture tick %d: the blades are still held" % i)
		assert_true(float(row[3]) > float(rows[i - 1][3]), "tick %d: while it is a cut it keeps travelling" % i)
		travelling += 1
		if float(row[4]) < keep:
			slow += 1
		if i < stopped:
			slid_before += absf(float(row[7]) - float(rows[i - 1][7]))
	assert_true(travelling >= 5, "fixture: the cut travels through a held contact for several ticks (%d)" % travelling)
	assert_true(slow >= 1, "a cut below 40%% of its ceiling is still a cut — no ratio law (%d)" % slow)
	assert_true(slid_before > 0.2, "the contact slides along the beaten blade (%.2f of its length)" % slid_before)
	assert_true(ended > 0, "the press is not endless: the guard on its stop arrests the cut inside the window")
	if ended > 0:
		assert_eq(int(rows[ended][2]), CombatPhase.Id.RECOVERY, "it ends in recovery")
		assert_true(float(rows[ended][4]) <= weapon.control_speed, "only once the press brought it under control (%.3f rad/s)" % float(rows[ended][4]))
		assert_true(float(rows[ended - 1][4]) > 0.0, "and it was still progressing on the tick before")
	## The manifold's stored Jn is cleared when the next substep records the
	## point, and a resting sample is zero once the blades are no longer
	## approaching. The press itself is the clash impulse.
	var clash := runner.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(clash != null and clash.number(DuelEventKeys.IMPULSE) > 0.0, "the press delivers a normal impulse (%.3f N·s)" % (0.0 if clash == null else clash.number(DuelEventKeys.IMPULSE)))

## A Long Guard blade that starts past the opponent's centre presses its torso
## back toward the wielder: clearing that overlap alone would push the bodies
## into each other. The bodies are a row in the same block, so the position
## stage never trades one overlap for another. (Recovery from a penetrating
## initial state, so the scene is placed, not reached — SCENARIO-REACHABILITY-001.)
## Fighter 0 in Long Guard along +x with fighter 1 `ahead` along the line and
## `aside` off it: at short range the blade starts past fighter 1's centre.
func _long_guard_through(ahead: float, aside: float) -> MatchState:
	var state := DuelFixture.state(_rules)
	var weapon := _rules.combatant(0).weapon
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, 0.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(state.fighter(1), ahead, aside, PI, deg_to_rad(135.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	state.weapon_body_contacts[0].phase = WeaponBodyContact.Phase.CONSTRAINING
	return state


func _apart(state: MatchState) -> float:
	return DuelGeometry.distance(state.fighter(0), state.fighter(1))


func test_clearing_a_sword_on_a_torso_never_drives_the_bodies_together() -> void:
	var apart := 2.0 * _rules.combatant(0).fighter.push_radius
	## Control: with the bodies clear of each other, clearing that overlap
	## draws them together — the tendency the body row must resist.
	var loose := _long_guard_through(0.6, 0.0)
	assert_true(_body(loose.fighter(0), loose.fighter(1)) < -_allowed(), "fixture: the blade starts inside the torso")
	RigidContactSolver.new().project(loose, _rules)
	assert_true(_apart(loose) < 0.6, "control: clearing it draws the free bodies together (%.4f m)" % _apart(loose))
	## Feasible: just off the line, turning the blade can clear the torso, so
	## both rows are met — the blade cleared and the bodies kept apart.
	var touching := _long_guard_through(0.53, 0.12)
	assert_true(_apart(touching) - apart < 0.04, "fixture: the bodies are within a correction of touching (%.4f m apart)" % _apart(touching))
	assert_true(_body(touching.fighter(0), touching.fighter(1)) < -_allowed(), "fixture: and the blade starts inside the torso (%.4f m)" % _body(touching.fighter(0), touching.fighter(1)))
	var solver := RigidContactSolver.new()
	for _pass in 3:
		solver.project(touching, _rules)
	assert_true(_apart(touching) >= apart - 1e-9, "the bodies are never driven into each other (%.5f m apart)" % _apart(touching))
	assert_true(_body(touching.fighter(0), touching.fighter(1)) >= -_allowed(), "and the blade is cleared to the slop (%.4f m)" % _body(touching.fighter(0), touching.fighter(1)))
	## Exactly on the line, with the blade start pressed axially into a torso
	## while the bodies already touch, no correction could meet both rows. That
	## state is unreachable in live play — the point meets the body first
	## (LONG-GUARD-INTERCEPT-001) — so it is not a scene to design the solver
	## around (SCENARIO-REACHABILITY-001).


## LONG-GUARD-INTERCEPT-001: a centred point meets an advancing body before
## the bodies can meet, and holding the walk cannot force the body through it.
## θ = 0 is the centred point, not the resting guard: the return carries it
## toward the committed side, so the walker starts close enough (1.8 m) that
## the point still meets him first. What yields is left to the physics; the
## scene mirrors, including the side a centred blade remembers.
const INTERCEPT_TICKS := 45


func _intercept(side: float) -> Array:
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	var weapon := _rules.combatant(0).weapon
	## The walker's own blade wound back out of the line. Its hilt still rides
	## in front of his centreline (SLASH-SHAPE-001), so the point may meet the
	## pommel he carries before it meets his torso: either way it is his.
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, side * deg_to_rad(135.0), 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(state.fighter(1), 0.0, 1.8, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	## The centred point sits inside the side deadzone, so arming it does not
	## commit a side. The match remembered the opening's right side for both
	## scenes; a mirror has to remember the opposite side, or the guard return
	## pulls both points the same way.
	state.fighter(1).weapon.stable_side = side
	state.fighter(1).weapon.swing_dir = -side
	state.fighter(0).weapon.swing_dir = -state.fighter(0).weapon.stable_side
	var closest := INF
	var deepest := 0.0
	var met_at := -1.0
	for _tick in INTERCEPT_TICKS:
		runner.push(PlayerCommand.create(state.tick, 0.0, 1.0), PlayerCommand.idle(state.tick))
		var walker := state.fighter(0)
		var guard := state.fighter(1)
		var distance := DuelGeometry.distance(walker, guard)
		closest = minf(closest, distance)
		if met_at < 0.0 and (runner.count(DuelEventTypes.BODY_POKE) > 0 or runner.count(DuelEventTypes.BLADE_CONTACT) > 0):
			met_at = distance
		if state.weapon_body_contacts[1].phase != WeaponBodyContact.Phase.OUTSIDE:
			deepest = maxf(deepest, -_body(guard, walker))
	return [runner, closest, deepest, met_at]


func test_a_centred_point_meets_an_advancing_body_before_the_fighters_do() -> void:
	var apart := 2.0 * _rules.combatant(0).fighter.push_radius
	var right := _intercept(-1.0)
	var runner: SimRunner = right[0]
	assert_true(float(right[3]) > apart + 0.5, "the guard's sword meets the walker first, well before the bodies could (%.3f m apart)" % float(right[3]))
	assert_true(float(right[1]) >= apart - 1e-9, "holding the walk never forces the bodies together through the point (closest %.3f m)" % float(right[1]))
	assert_true(float(right[2]) <= _allowed(), "the point never sinks into the walker beyond the slop (worst %.4f m)" % float(right[2]))
	var left := _intercept(1.0)
	var mirror: SimRunner = left[0]
	for slot in 2:
		var r := runner.state.fighter(slot)
		var l := mirror.state.fighter(slot)
		assert_near(l.y, r.y, 1e-9, "slot %d: the mirrored scene ends the same distance along the line" % slot)
		assert_near(l.x, -r.x, 1e-9, "slot %d: at the reflected lateral position" % slot)
		assert_near(l.weapon.angle, -r.weapon.angle, 1e-9, "slot %d: with the reflected θ" % slot)


## The point controls distance only while it is centred: beat it aside and the
## same walk closes to the bodies. No range barrier, only geometry. The cut
## that beats the guard aside keeps driving while it travels (one interrupt
## law) and that press shoves the defender back, so the walk is held long
## enough for that push to settle — the claim is where the walk ends up, not
## how fast.
func test_beating_a_long_guard_aside_lets_the_body_close() -> void:
	var apart := 2.0 * _rules.combatant(0).fighter.push_radius
	var measure := WeaponKinematics.strike_reach(_rules.combatant(0), _rules.combatant(1))
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	var weapon := _rules.combatant(0).weapon
	ContactFixture.arm(state.fighter(0), 0.0, 0.0, PI / 2.0, deg_to_rad(-110.0), 8.0, CombatPhase.Id.ACTIVE_THREAT, 1.0, weapon)
	state.fighter(0).weapon.swing_dir = 1.0
	## Clear of the cutter's sword: inside about 2.15 m the Long Guard's point
	## starts lying through the cutter's handle and hands, wound back at −110°.
	ContactFixture.arm(state.fighter(1), 0.0, 2.2, -PI / 2.0, 0.0, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	assert_true(_blades(state).x > 0.0, "fixture: the swords start apart (%.3f m)" % _blades(state).x)
	var closest := INF
	var displaced := false
	for tick in 180:
		var walk := PlayerCommand.create(state.tick, 0.0, 1.0) if tick >= 8 else PlayerCommand.idle(state.tick)
		runner.push(walk, PlayerCommand.idle(state.tick))
		## Bodies on the platform; one pushed over its edge no longer stands
		## against the other.
		if not (state.fighter(0).is_falling or state.fighter(1).is_falling):
			closest = minf(closest, DuelGeometry.distance(state.fighter(0), state.fighter(1)))
		displaced = displaced or absf(state.fighter(1).weapon.angle) > GuardPoseField.THRUST_LEAVE
	assert_true(runner.count(DuelEventTypes.BLADE_CONTACT) >= 1, "fixture: the cut meets the Long Guard's blade")
	assert_true(displaced, "the clash beats the point out of the corridor")
	assert_true(closest < measure - 0.5, "and the same walk then closes well inside the point's measure (%.3f vs %.3f m)" % [closest, measure])
	assert_true(closest >= apart - 1e-9, "to the bodies, never through them (%.4f m)" % closest)


func test_held_pressure_mirrors_exactly() -> void:
	var right := _walk_into_guard(-1.0, true)
	var left := _walk_into_guard(1.0, true)
	var r: SimRunner = right[0]
	var l: SimRunner = left[0]
	assert_true(int(right[3]) > 20 and int(left[3]) > 20, "fixture: both sides press for most of the walk")
	assert_ne(float(right[1]), float(left[1]), "fixture: the two scenes are mirror images, not copies")
	for slot in 2:
		var rf := r.state.fighter(slot)
		var lf := l.state.fighter(slot)
		assert_near(lf.y, rf.y, 1e-7, "slot %d: the same distance along the line" % slot)
		assert_near(lf.x, -rf.x, 1e-9, "slot %d: the reflected lateral position" % slot)
		## Positions mirror through shared headings, not the bit-exact point
		## reflection the heading trig would make. Rules 57's authority return
		## carries a sub-microradian angular difference into the next ticks, so
		## the along-line residual measured here is about 4.3e-8 m (it was
		## about 3.5e-9 before the return read authority). Lateral position
		## stays inside a nanometre. A miss would be centimetres.
		assert_near(lf.weapon.angle, -rf.weapon.angle, 1e-6, "slot %d: the reflected θ" % slot)
		assert_near(lf.weapon.speed, -rf.weapon.speed, 1e-6, "slot %d: the reflected θ̇" % slot)

## CONTACT-FALLBACK-001: an adversarial storm, built point-symmetric — the
## bodies driving together at 6.9 m/s with crossed swords, headings spinning at
## 8 rad/s, blades swinging into each other — a state far outside play that
## spends the whole re-hold budget in one tick. The fallback carries the rest
## of that tick without letting the swords through each other: no held overlap
## beyond the slop, no centreline ever crossing, the blade staying on the side
## it met from, θ̇ left as the contact left it rather than zeroed, the duel
## still each other's exact reflection, and the next tick back to the full
## budget. The storm is the bound. Seed 122 does not reach the fallback under
## rules 57 (`test_the_seed_122_fast_slide_fallback_is_bounded_and_escapable`).
## A torso hit during the storm is allowed: zero torso
## hits was never the re-hold invariant. The pass is the budget spent once,
## the bounded fallback, the mirror, and the speed the contact left.
func test_a_rehold_storm_falls_back_without_tunnelling_and_stays_mirrored() -> void:
	## ARRANGE: the point-symmetric storm.
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var state := runner.state
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, -STORM_DISTANCE * 0.5, 0.0, STORM_FACING)
	DuelFixture.place(b, STORM_DISTANCE * 0.5, 0.0, PI + STORM_FACING)
	a.vx = STORM_CLOSING
	a.vy = STORM_LATERAL
	b.vx = -STORM_CLOSING
	b.vy = -STORM_LATERAL
	for fighter: FighterState in [a, b]:
		fighter.turn_rate = STORM_TURN
		fighter.weapon.angle = STORM_ANGLE
		fighter.weapon.speed = STORM_SWING
	var start := _blades(state)
	assert_true(start.x > 0.0, "fixture: the swords start apart, so anything crossed later the solver did (%.4f m)" % start.x)
	## ACT
	var worst := 0.0
	var mirror := 0.0
	var crossings := 0
	var flipped := 0
	var fallback_tick := -1
	var fallback_swing := 0.0
	for tick in STORM_TICKS:
		runner.push(PlayerCommand.create(state.tick, 0.0, 1.0), PlayerCommand.create(state.tick, 0.0, 1.0))
		var blades := _blades(state)
		if state.blade_contact.phase != SwordContactSet.Phase.SEPARATED:
			worst = maxf(worst, -blades.x)
			if blades.y != start.y:
				flipped += 1
		if _centrelines(state) <= SimMath.EPSILON:
			crossings += 1
		if fallback_tick < 0 and runner.simulation.diagnostics.rehold_budget_exhausted > 0:
			fallback_tick = tick
			fallback_swing = a.weapon.speed
		mirror = maxf(mirror, absf(a.x + b.x) + absf(a.y + b.y) + absf(a.vx + b.vx) + absf(a.vy + b.vy) + absf(a.weapon.angle - b.weapon.angle) + absf(a.weapon.speed - b.weapon.speed) + absf(SimMath.wrap_angle(a.facing - b.facing - PI)))
	## ASSERT
	assert_true(fallback_tick >= 0, "fixture: the storm spends the whole re-hold budget")
	assert_eq(runner.simulation.diagnostics.rehold_budget_exhausted, 1, "on one tick only; the next starts with the full budget")
	assert_true(state.blade_contact.phase != SwordContactSet.Phase.SEPARATED or runner.count(DuelEventTypes.BLADE_CONTACT) > 0, "fixture: the swords met")
	assert_true(worst <= _allowed(), "no held sword sinks beyond the slop (worst %.4f m)" % worst)
	assert_eq(crossings, 0, "no centreline ever crosses the other")
	assert_eq(flipped, 0, "the blade stays on the side it met from")
	assert_true(absf(fallback_swing) > 1.0, "the fallback leaves θ̇ as the contact left it, never zeroed (%.2f rad/s)" % fallback_swing)
	assert_true(mirror < 1.0e-6, "the duel stays its own reflection to rounding (%s; the suite's mirror standard)" % String.num_scientific(mirror))
	assert_eq(runner.count(DuelEventTypes.CONTACT_SATURATED), 0, "and the contact loop never saturates")
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())

# ── CONTACT-REHOLD-FALLBACK-001: the fast-slide fallback, as play reaches it ─


## Seed 122, wander pilots 11 and 23, stamina neutral. Rules 52–54 spent the
## re-hold budget at tick 854. Rules 55 did not. Rules 56 spent it once at
## that tick, while authority sat on the floor. Rules 57 recovers, and this
## seed spends nothing through 2000 ticks in the trace, and through
## `REHOLD_WINDOW` here. The constructed storm owns the fallback's behavior.
const REHOLD_SEED := 122
const REHOLD_PILOTS := [11, 23]
const REHOLD_WINDOW := 1200


## Seed 122 driven from tick 0 to `through`: [the runner, each tick's state hash].
func _seed_122(through: int) -> Array:
	var runner := SimRunner.create(DuelFixture.stamina_neutral(DuelFixture.rules()), REHOLD_SEED)
	var first := Pilot.wander(REHOLD_SEED, int(REHOLD_PILOTS[0]))
	var second := Pilot.wander(REHOLD_SEED, int(REHOLD_PILOTS[1]))
	var hashes := PackedStringArray()
	while runner.state.tick < through:
		runner.push(first.command(runner.state, 0), second.command(runner.state, 1))
		hashes.append(StateHasher.hash_state(runner.state))
	return [runner, hashes]


## CONTACT-REHOLD-FALLBACK-001 as representative play reaches it only in the
## constructed storm. Seed 122 spent the budget at tick 854 under rules 56
## because a sword stayed at the authority floor. Rules 57 recovers that
## deficit, and the same production input spends nothing through the window.
## The storm above still proves the fallback stays bounded.
func test_the_seed_122_fast_slide_fallback_is_bounded_and_escapable() -> void:
	var played := _seed_122(REHOLD_WINDOW)
	var again := _seed_122(REHOLD_WINDOW)
	var runner := played[0] as SimRunner
	assert_eq(runner.simulation.diagnostics.rehold_fallback_ticks, PackedInt32Array(), "this production duel does not spend the re-hold budget")
	assert_eq(runner.simulation.diagnostics.rehold_budget_exhausted, 0, "and the counter stays at zero")
	assert_eq(played[1], again[1], "deterministic: the same input replays the same states, tick for tick")
	assert_eq(runner.count(DuelEventTypes.CONTACT_SATURATED), 0, "the contact loop never saturates")
	assert_true(runner.is_sound(), "every tick finite and physically possible (%s)" % runner.violation_summary())



## A steel contact episode is one impact, however the solver holds it.
## The constructed case is a resting overlap: both blades sit on the guard
## the return is already tracking, 2 mm through each other, so idle has no
## separating motor. Re-holds of that overlap emit no impact. The storm
## owns the constructed fallback. Seed 122 does not reach it.
func test_a_contact_episode_is_one_impact_event_however_the_solver_holds_it() -> void:
	for side: float in [1.0, -1.0]:
		var bind := _bind(side)
		var formed := bind.count(DuelEventTypes.BLADE_CONTACT)
		assert_true(bind.state.blade_contact.hold_count() > 0, "side %+.0f fixture: the overlap is held" % side)
		var apart := 0
		for _t in MAX_WITNESS_TICKS:
			bind.push(PlayerCommand.idle(bind.state.tick), PlayerCommand.idle(bind.state.tick))
			if bind.state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
				apart += 1
		assert_eq(apart, 0, "side %+.0f: a resting overlap stays in contact" % side)
		assert_eq(bind.count(DuelEventTypes.BLADE_CONTACT), formed, "side %+.0f: holding it emits no new impact" % side)

# ── BLADE-ESCAPE-001: a bind may last while it is maintained, never trap ───


## The test-harness watchdog: an escape witness fails rather than runs on
## forever. A test budget, never a combat rule — how long a bind lasts is the
## players'.
const MAX_WITNESS_TICKS := 60
## A witness bind holds at least this long with both fighters idle: it is a
## bind, not a contact already coming apart.
const HELD_IDLE_TICKS := 20
## The canonical bind is a resting overlap, not a walked-in clash. Both blades
## sit on the guard the return already tracks (±guard_angle), 2 mm through
## each other, so idle has no separating motor: the hold is the solver's.
## A walked-in bind whose angles have left that guard can be drawn apart by
## the return, and that is not a release rule. `side` mirrors it.
const REST_OVERLAP_M := 0.002


## The resting overlap on `side` (+1 or −1), after one idle tick so the hold
## is the solver's.
func _bind(side: float) -> SimRunner:
	var runner := SimRunner.create(_rules, 5)
	runner.skip_intro()
	var spec := _rules.combatant(0)
	var guard := spec.weapon.guard_angle
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, PI / 2.0)
	a.weapon.reset(side * guard)
	DuelFixture.place(b, 0.0, ContactFixture.crossed_guard_separation(spec, -REST_OVERLAP_M, side), -PI / 2.0)
	b.weapon.reset(-side * guard)
	runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	return runner


const ESCAPE_WITNESSES := [
	[1, "back", "retreat"],
	[1, "left", "a lateral step"],
	[1, "wind", "winding the blade back off the other"],
]


## Fork `bind` and drive the fighters with `kinds` for up to
## `MAX_WITNESS_TICKS`: [the tick it separated (−1 never), the blades' surface
## gap at the end, held rows and points at the end, torso hits, sound, deepest
## overlap].
func _escape(bind: SimRunner, kinds: Array) -> Array:
	var fork := StateFork.of(bind)
	var parted := -1
	var deepest := 0.0
	for t in MAX_WITNESS_TICKS:
		var tick := fork.state.tick
		fork.push(_bind_command(String(kinds[0]), tick, t), _bind_command(String(kinds[1]), tick, t))
		if fork.state.blade_contact.phase != SwordContactSet.Phase.SEPARATED:
			deepest = maxf(deepest, -_blades(fork.state).x)
		if parted < 0 and fork.state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
			parted = t + 1
			## A few more ticks: nothing held may linger once the swords are apart.
			for after in 3:
				fork.push(_bind_command(String(kinds[0]), fork.state.tick, t + 1 + after), _bind_command(String(kinds[1]), fork.state.tick, t + 1 + after))
			break
	var contact := fork.state.blade_contact
	return [parted, _blades(fork.state).x, contact.hold_count() + contact.point_count, _torso_hits(fork), fork.is_sound(), deepest]


## BLADE-ESCAPE-001: there is no scripted bind winner and no automatic release.
## This fixture is the equilibrium case: both blades rest on the guard the
## return already tracks, so idle keeps the overlap. A separating command
## still takes it apart. Pressing stays legal and never tunnels; nothing
## requires the press to part. Other idle contacts may separate when the
## return draws a blade off the steel, and that is not this law.
func test_ordinary_separating_input_takes_a_bind_apart() -> void:
	for witness: Array in ESCAPE_WITNESSES:
		var label := String(witness[2])
		## ARRANGE: the constructed bind, and that it is one.
		var bind := _bind(1.0)
		var contact := bind.state.blade_contact
		assert_true(contact.hold_count() > 0 and contact.point_count > 0, "%s fixture: the blades are held in contact" % label)
		var idle := _escape(bind, ["idle", "idle"])
		assert_true(int(idle[0]) < 0 or int(idle[0]) >= HELD_IDLE_TICKS, "%s fixture: idle, it stays bound (%d)" % [label, int(idle[0])])
		## PERTURB: the escaping fighter's input; the other gives none.
		var kinds := ["idle", "idle"]
		kinds[int(witness[0])] = witness[1]
		## ACT
		var escaped := _escape(bind, kinds)
		var pressed := _escape(bind, ["press", "press"])
		var mirrored := _escape(_bind(-1.0), kinds)
		## ASSERT
		assert_true(int(escaped[0]) > 0, "%s: the swords part before the watchdog (%d ticks)" % [label, int(escaped[0])])
		assert_true(float(escaped[1]) > _rules.combat.separation_epsilon, "%s: with a real gap (%.4f m)" % [label, float(escaped[1])])
		assert_eq(int(escaped[2]), 0, "%s: and nothing is held once they are apart" % label)
		assert_eq(int(escaped[3]), 0, "%s: no torso is struck on the way out" % label)
		assert_true(bool(escaped[4]), "%s: every tick legal" % label)
		assert_eq(int(mirrored[0]), int(escaped[0]), "%s: the mirrored bind parts on the same tick" % label)
		assert_true(bool(pressed[4]) and float(pressed[5]) <= _allowed(), "%s: pressing in is legal and never tunnels (worst %.4f m)" % [label, float(pressed[5])])


## BLADE-CONTACT-RELEASE-001: a held blade contact whose geometry has genuinely
## separated keeps nothing — no point, no held row, no warm start — on the
## very tick the gap opens, whatever its history.
func test_a_separated_blade_contact_keeps_nothing() -> void:
	## ARRANGE: the constructed bind, held with real impulse.
	var bind := _bind(1.0)
	var contact := bind.state.blade_contact
	var held := 0.0
	for i in contact.hold_count():
		held += absf(contact.hold_normal[i])
	assert_true(contact.hold_count() > 0, "fixture: the blades are held")
	## PERTURB: the second fighter stood well clear of the first, in one step,
	## along the held point's normal (from the second sword toward the first).
	var fork := StateFork.of(bind)
	var b := fork.state.fighter(1)
	var away := Vector2(contact.point_nx[0], contact.point_ny[0]) * -0.25
	b.x += away.x
	b.y += away.y
	## ACT
	fork.push(PlayerCommand.idle(fork.state.tick), PlayerCommand.idle(fork.state.tick))
	## ASSERT
	assert_true(_blades(fork.state).x > _rules.combat.separation_epsilon, "fixture: the blades are apart (%.4f m)" % _blades(fork.state).x)
	assert_eq(fork.state.blade_contact.point_count, 0, "no contact point survives the gap")
	assert_eq(fork.state.blade_contact.hold_count(), 0, "nor any held row (%.4f N·s were held)" % held)
	assert_eq(fork.state.blade_contact.phase == SwordContactSet.Phase.CONTACTING, false, "and the contact is no longer touching")
	assert_true(fork.is_sound(), "every tick legal")


static func _bind_command(kind: String, tick: int, t: int) -> PlayerCommand:
	match kind:
		"press":
			return PlayerCommand.create(tick, 0.0, 0.0, true, true)
		"wind":
			return PlayerCommand.create(tick, 0.0, 0.0, t == 0, false)
		"back":
			return PlayerCommand.create(tick, 0.0, -1.0)
		"right":
			return PlayerCommand.create(tick, 1.0, 0.0)
		"left":
			return PlayerCommand.create(tick, -1.0, 0.0)
	return PlayerCommand.idle(tick)


# ── DEFLECTION-001: the production-input witness ─────────────────────────────


## Each tick's physical state, for comparing a scene with its relabelled twin.
func _deflection_physics(state: MatchState) -> String:
	var parts := PackedStringArray()
	for slot in 2:
		var f := state.fighter(slot)
		parts.append(var_to_str([f.x, f.y, f.vx, f.vy, f.facing, f.turn_rate, f.weapon.angle, f.weapon.speed, f.weapon.phase, f.weapon.commitment, f.weapon.recovery_left, f.health]))
	return "|".join(parts)


## Rules 52 met this on seed 5 at tick 905; rules 54's guard return moved it
## to seed 5 tick 472. Rules 56: seed 19, clash tick 1892. Rules 57 recovers
## authority and that seed has none in 2400 ticks. The same pilots on seed 5
## deflect slot 0's cut; the clash tick below only finds that cut. It is not
## a gameplay contract. The assertions are the impulse, the missing arrest,
## and the cutter striking nothing. Re-read inside the wander pilots, not a
## new stick.
const DEFLECTION_SEED := 5
const DEFLECTION_CLASH_TICK := 1296
const DEFLECTION_LEAD := 1
const DEFLECTION_CUTTER := 0
const DEFLECTION_TICKS := 30


## The witness duel played to one tick before the clash, and the commands its
## pilots give over the next `DEFLECTION_TICKS`: [runner, [[command_0,
## command_1], ...]].
func _before_deflection() -> Array:
	var played := SimRunner.create(DuelFixture.stamina_neutral(DuelFixture.rules()), DEFLECTION_SEED)
	var pilots: Array[Pilot] = [Pilot.wander(DEFLECTION_SEED, 11), Pilot.wander(DEFLECTION_SEED, 23)]
	while played.state.tick < DEFLECTION_CLASH_TICK - DEFLECTION_LEAD:
		played.push(pilots[0].command(played.state, 0), pilots[1].command(played.state, 1))
	var live := StateFork.of(played)
	var commands: Array = []
	for _i in DEFLECTION_TICKS:
		var pair := [pilots[0].command(live.state, 0), pilots[1].command(live.state, 1)]
		commands.append(pair)
		live.push(pair[0], pair[1])
	return [played, commands]


## The witness `played` forked under `rules` and fed `commands`, appending each
## tick's physical state to `trace` (`_physics`).
func _deflected_cut(played: SimRunner, commands: Array, rules: DuelRules, trace: Array[String] = []) -> SimRunner:
	var fork := SimRunner.create(rules, DEFLECTION_SEED)
	StateFork.copy(played.state, fork.state)
	for pair: Array in commands:
		fork.push(pair[0], pair[1])
		trace.append(_deflection_physics(fork.state))
	return fork


## DEFLECTION-001: a deflection is what a redirected attack did, never a
## mechanic. The scene proves itself: before the clash the cut is on the line
## (its own planted sweep reaches the defender, the reading DEFLECTION-001
## marks on). Protective steel takes a positive impulse that does not arrest
## the cut, and the cut ends having struck nothing — so it is a deflection,
## credited to the defender, once, and not a parry. Then NO-LABEL-PHYSICS-001:
## the same scene with that steel declared non-protective moves identically on
## every tick and emits no deflection.
func test_a_redirected_cut_that_strikes_nothing_is_a_deflection() -> void:
	## ARRANGE: the cut on the line, just before the clash.
	var rules := DuelFixture.stamina_neutral(DuelFixture.rules())
	var witness := _before_deflection()
	var played: SimRunner = witness[0]
	var commands: Array = witness[1]
	var cutter := played.state.fighter(DEFLECTION_CUTTER)
	var defender := played.state.fighter(1 - DEFLECTION_CUTTER)
	var reading := InitiativeModel.estimate(cutter, rules.spec_of(cutter), defender, rules.spec_of(defender), rules.combat, ThreatEstimate.new(), ThreatContinuation.planted())
	assert_true(CombatPhase.is_swinging(cutter.weapon.phase), "fixture: slot %d's cut is in flight" % DEFLECTION_CUTTER)
	assert_true(reading.within_horizon, "fixture: and on the line — its planted sweep reaches the defender")
	## ACT
	var trace: Array[String] = []
	var runner := _deflected_cut(played, commands, rules, trace)
	## ASSERT: physically a redirection that did not arrest...
	var contact := runner.first(DuelEventTypes.BLADE_CONTACT)
	assert_true(contact != null and contact.actor == DEFLECTION_CUTTER, "the guard meets the cut")
	if contact == null:
		return
	assert_true(contact.number(DuelEventKeys.IMPULSE) > 0.0, "with a solved, positive impulse")
	assert_false(bool(contact.data[DuelEventKeys.ARRESTED_1 if DEFLECTION_CUTTER == 1 else DuelEventKeys.ARRESTED_0]), "that does not arrest it")
	for event in runner.events:
		if event.type == DuelEventTypes.BODY_HIT:
			assert_true(event.actor != DEFLECTION_CUTTER, "and the cut strikes nothing")
	## ...so it is labelled a deflection when the attack ends, never a parry.
	var deflections := DuelFixture.of_type(runner.events, DuelEventTypes.DEFLECTION)
	assert_eq(deflections.size(), 1, "a redirected cut that struck nothing is one deflection")
	if deflections.is_empty():
		return
	assert_true(deflections[0].tick >= contact.tick, "decided when the attack ended, not before the contact")
	assert_eq(deflections[0].actor, 1 - DEFLECTION_CUTTER, "credited to the defender")
	assert_eq(deflections[0].target, DEFLECTION_CUTTER, "against the attacker")
	assert_eq(runner.count(DuelEventTypes.PARRY), 0, "an unarrested cut is not a parry")
	assert_eq(runner.count(DuelEventTypes.ATTACK_WHIFFED), 0, "and having met steel it is not a whiff")
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())
	## NO-LABEL-PHYSICS-001: the label is a reading.
	var inert := DuelFixture.stamina_neutral(DuelFixture.rules())
	inert.combatant(1 - DEFLECTION_CUTTER).weapon.blade_protects = false
	inert.combatant(1 - DEFLECTION_CUTTER).weapon.crossguard_protects = false
	var silenced_trace: Array[String] = []
	var silenced := _deflected_cut(played, commands, inert, silenced_trace)
	assert_eq(silenced.count(DuelEventTypes.DEFLECTION), 0, "perturbed: non-protective steel deflects nothing")
	assert_eq(silenced_trace.size(), trace.size(), "fixture: every tick traced")
	assert_eq(silenced_trace, trace, "yet every tick moves identically")
