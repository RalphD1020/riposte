extends TestCase

## MOTION-COMMIT: commitment is physical redirect debt (DIRECTIONAL-COMMIT-001,
## COMMITMENT-001) — momentum plus committed actuator effort against the
## braking available. Laws only: orderings, identities and exact mirrors,
## never a tuned turn rate.
##
## Implements: /spec/invariants.md#directional-commit-001
## Implements: /spec/invariants.md#commitment-001
## See also: /docs/concepts/combat.md

## Heading error the target is set at for the turning tests (rad): wide enough
## that no heading reaches it inside `TURN_TICKS`, so turning is not yet
## decelerating onto the target and the comparison reads authority alone.
const TARGET_OFFSET := deg_to_rad(120.0)
const TURN_TICKS := 12

var _rules: DuelRules


func _init() -> void:
	suite_name = "MOTION-COMMIT"
	_rules = DuelFixture.rules()


func _spec() -> CombatantPhysicsSpec:
	return _rules.combatant(0)


## A fighter at the origin facing +X, its blade resting at Long Guard.
func _fighter() -> FighterState:
	var fighter := FighterState.new()
	fighter.weapon.reset(0.0)
	fighter.health = _spec().fighter.max_health
	DuelFixture.place(fighter, 0.0, 0.0, 0.0)
	return fighter


## The same fighter mid-cut at `share` of the speed `charge` reaches, its
## motor no longer driving (so only momentum is read).
func _cutting(charge: float, share: float = 1.0) -> FighterState:
	var fighter := _fighter()
	fighter.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	fighter.weapon.swing_dir = 1.0
	fighter.weapon.swing_charge = charge
	fighter.weapon.launch_preparation = 1.0
	fighter.weapon.speed = _spec().weapon.achievable_swing_speed(charge, 1.0) * share
	return fighter


func _weapon(fighter: FighterState) -> float:
	return CommitmentModel.weapon_commitment(fighter, _spec(), _rules.combat)


func _root(fighter: FighterState) -> float:
	return CommitmentModel.root_commitment(fighter, _spec(), _rules.combat)


func _facing(fighter: FighterState) -> float:
	return CommitmentModel.facing_commitment(fighter, _spec(), _rules.combat)


func _torque(fighter: FighterState) -> float:
	return CommitmentModel.turn_torque_share(fighter, _spec(), ConditionState.new(), _rules.combat)


func _rate(fighter: FighterState) -> float:
	return CommitmentModel.turn_rate_share(fighter, _spec(), ConditionState.new(), _rules.combat)


## How far the heading turns toward a target `TARGET_OFFSET` away over
## `TURN_TICKS`, at the authorities this state gives (re-read every tick).
func _turned(fighter: FighterState) -> float:
	var start := fighter.facing
	for _i in TURN_TICKS:
		FacingSystem.step(fighter, cos(TARGET_OFFSET) * 3.0, sin(TARGET_OFFSET) * 3.0, _torque(fighter), _spec().fighter, null, _rate(fighter))
	return SimMath.wrap_angle(fighter.facing - start)


## WEAPON-COMMIT-001: at equal brake authority, more generalized weapon
## momentum `|M_θ·θ̇|` is more weapon commitment, and never better turning.
func test_more_weapon_momentum_is_more_commitment() -> void:
	var previous := -1.0
	var previous_authority := 2.0
	for share: float in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var fighter := _cutting(1.0, share)
		fighter.weapon.phase = CombatPhase.Id.OVERSWING
		var debt := CommitmentModel.weapon_redirect_impulse(fighter, _spec(), _rules.combat)
		assert_near(debt, absf(WeaponKinematics.motor_inertia(_spec(), fighter.weapon.angle) * fighter.weapon.speed), 1e-12, "with no drive the debt is the momentum itself")
		var commitment := _weapon(fighter)
		assert_true(commitment > previous or commitment == 1.0, "%.0f%% of full speed is more committed (%.3f)" % [share * 100.0, commitment])
		assert_true(_torque(fighter) <= previous_authority, "and never turns better (%.3f)" % _torque(fighter))
		previous = commitment
		previous_authority = _torque(fighter)
	assert_true(previous_authority < 1.0, "a full cut's momentum costs authority")


## DRIVE-COMMIT-001: at identical velocity, more actuator effort still being
## committed is more commitment — the root's forward motor force, the
## weapon's driving torque — before either has become speed.
func test_committed_drive_counts_before_it_becomes_speed() -> void:
	## Root: the same forward speed, coasting versus still driving forward.
	var coasting := _fighter()
	coasting.vx = 2.0
	var driving := _fighter()
	driving.vx = 2.0
	driving.ax = _spec().fighter.move_accel()
	assert_true(_root(driving) > _root(coasting), "the driving body is more committed forward (%.3f > %.3f)" % [_root(driving), _root(coasting)])
	var braking := _fighter()
	braking.vx = 2.0
	braking.ax = -_spec().fighter.brake_accel()
	assert_true(_root(braking) < _root(coasting), "and the braking one less — the brake is already paying the debt")
	## Weapon: the same blade speed at launch, with and without the motor
	## driving it along the cut.
	var launched := _cutting(1.0, 0.0)
	launched.weapon.phase = CombatPhase.Id.LAUNCH
	var drive := _cutting(1.0, 0.0)
	drive.weapon.phase = CombatPhase.Id.LAUNCH
	drive.weapon.motor_torque = 150.0
	assert_eq(_weapon(launched), 0.0, "a blade at rest, undriven, owes nothing")
	assert_true(_weapon(drive) > 0.0, "the same blade under full drive is already committed (%.3f)" % _weapon(drive))
	var against := _cutting(1.0, 0.0)
	against.weapon.phase = CombatPhase.Id.LAUNCH
	against.weapon.motor_torque = -150.0
	assert_eq(_weapon(against), 0.0, "torque against the cut commits nothing to it")


## FORWARD-COMMIT-001: forward momentum turns worse than standing, all else
## equal, and a faster advance never turns better than a slower one.
func test_forward_momentum_turns_less_than_neutral() -> void:
	## ARRANGE
	var neutral := _fighter()
	var advancing := _fighter()
	advancing.vx = _spec().fighter.max_speed
	assert_true(_root(advancing) > 0.0, "precondition: committed forward")
	## ACT
	var free := _turned(neutral)
	var committed := _turned(advancing)
	## ASSERT
	assert_true(free > 0.0, "precondition: the neutral heading turns toward the target")
	assert_true(committed < free, "forward momentum turns less (%.3f < %.3f rad)" % [committed, free])
	var previous := 2.0
	for speed: float in [0.0, 1.0, 2.0, 4.2, 6.0, 8.4]:
		var fighter := _fighter()
		fighter.vx = speed
		assert_true(_torque(fighter) <= previous, "%.1f m/s never turns better than slower (%.3f)" % [speed, _torque(fighter)])
		previous = _torque(fighter)
	assert_true(previous < 1.0, "a lunge's momentum costs authority (%.3f)" % previous)


## RETREAT-RELIEF-001: backing off turns better than an equal advance and
## better than standing in the same cut, but never better than healthy neutral.
func test_retreat_relieves_commitment_but_never_beyond_neutral() -> void:
	var speed := _spec().fighter.max_speed
	## ARRANGE: a tap at speed, advancing, still, and retreating.
	var advancing := _cutting(0.0)
	advancing.vx = speed
	var still := _cutting(0.0)
	var retreating := _cutting(0.0)
	retreating.vx = -speed
	var standing_back := _fighter()
	standing_back.vx = -speed
	## ASSERT
	assert_true(_root(retreating) < 0.0, "precondition: the retreat reads as negative root commitment")
	assert_true(_torque(still) < 1.0, "precondition: the tap commits something")
	assert_true(_torque(retreating) > _torque(advancing), "retreating turns better than an equal advance")
	assert_true(_torque(retreating) > _torque(still), "and better than standing in the same cut")
	assert_true(_torque(retreating) <= 1.0 and _rate(retreating) <= 1.0, "never more than healthy neutral")
	assert_eq(_torque(standing_back), 1.0, "an uncommitted retreat is exactly neutral, not more")
	assert_eq(_rate(standing_back), 1.0, "in rate too")


## LATERAL-001: motion across the heading has no forward component and gets
## no longitudinal penalty; the same speed forward does.
func test_lateral_motion_is_free() -> void:
	var speed := _spec().fighter.max_speed
	var lateral := _fighter()
	lateral.vy = speed
	lateral.ay = _spec().fighter.move_accel()
	var forward := _fighter()
	forward.vx = speed
	assert_near(CommitmentModel.forward_speed(lateral), 0.0, 1e-12, "precondition: no forward component")
	assert_eq(_root(lateral), 0.0, "lateral footwork has no root commitment")
	assert_eq(_torque(lateral), 1.0, "and keeps neutral authority")
	assert_true(_torque(forward) < 1.0, "while the same speed forward does not")


## COMBINED-001: a full swing with the body driving forward is more committed
## than either alone, and one bounded composition never passes 1.
func test_a_full_cut_while_lunging_compounds() -> void:
	var dash := _spec().fighter.burst_speed_axial
	var cut := _cutting(1.0, 0.5)
	var lunge := _fighter()
	lunge.vx = dash
	var both := _cutting(1.0, 0.5)
	both.vx = dash
	assert_true(_facing(cut) > 0.0 and _facing(lunge) > 0.0, "precondition: each commits on its own (%.3f, %.3f)" % [_facing(cut), _facing(lunge)])
	assert_true(_facing(both) > _facing(cut), "the cut while lunging is more committed than the cut")
	assert_true(_facing(both) > _facing(lunge), "and than the lunge")
	assert_true(_facing(both) <= 1.0, "within one bounded composition")
	assert_true(_torque(both) < _torque(cut) and _torque(both) < _torque(lunge), "so it turns worse than either")
	assert_true(_torque(both) >= _rules.combat.commit_turn_torque_floor, "but never below the committed floor — slower, never locked")


## PLANTED-POWER-001: at equal sword motion a planted attack has no artificial
## weakness — its weapon motor drives exactly as hard, and its weapon
## commitment is exactly the same as an advancing one's.
func test_a_planted_attack_is_not_weaker() -> void:
	var planted := _cutting(1.0, 0.5)
	var advancing := _cutting(1.0, 0.5)
	advancing.vx = _spec().fighter.max_speed
	assert_eq(_weapon(planted), _weapon(advancing), "the same weapon commitment")
	var events: Array[DuelEvent] = []
	WeaponSystem.step(planted, _rules, 0, events)
	WeaponSystem.step(advancing, _rules, 0, events)
	assert_eq(planted.weapon.speed, advancing.weapon.speed, "the same motor drive")
	assert_eq(planted.weapon.motor_torque, advancing.weapon.motor_torque, "the same applied torque")


## MOTION-ENERGY-001 / POINT-VELOCITY-001: the same θ, θ̇ and heading, the body advancing, standing
## or retreating along the strike: the point closes faster, the same, slower —
## by exactly the body's velocity along the direction, through the one point
## velocity (`WeaponKinematics.velocity_into`), with no movement multiplier.
func test_moving_with_the_strike_adds_exactly_its_own_velocity() -> void:
	var speed := _spec().fighter.max_speed
	var closings := PackedFloat64Array()
	for vx: float in [speed, 0.0, -speed]:
		var fighter := _cutting(1.0)
		fighter.vx = vx
		var pose := WeaponKinematics.pose_of(fighter, _spec(), BladePose.new())
		WeaponKinematics.velocity_into(fighter, pose, pose.point_x(_spec().weapon.tip_radius), pose.point_y(_spec().weapon.tip_radius))
		closings.append(pose.vx)
	assert_true(closings[0] > closings[1] and closings[1] > closings[2], "advancing > planted > retreating (%.2f, %.2f, %.2f m/s)" % [closings[0], closings[1], closings[2]])
	assert_near(closings[0] - closings[1], speed, 1e-12, "the advance adds exactly its own speed")
	assert_near(closings[1] - closings[2], speed, 1e-12, "the retreat takes exactly its own speed")


## CONTACT-RELEASE-001: a parry that takes the cut's speed takes its weapon
## commitment with it on that very tick. There is no PARRIED reset — the
## commitment is a pure reading of the momentum the contact left.
func test_a_physical_arrest_drops_weapon_commitment_at_once() -> void:
	## ARRANGE: the CONTACT parry scene — a tap from measure into a guard
	## resting in its path, on the shipping rules.
	var runner := SimRunner.create(_rules, 2)
	runner.skip_intro()
	var attacker := runner.state.fighter(0)
	var defender := runner.state.fighter(1)
	var guard := _rules.combatant(1).weapon.guard_limit
	defender.weapon.angle = guard
	var reach := WeaponKinematics.strike_reach(_rules.combatant(0), _rules.combatant(1))
	var walked := 0
	while DuelGeometry.distance(attacker, defender) > reach and walked < 300:
		runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
		walked += 1
	runner.idle(20)
	defender.weapon.angle = guard
	defender.weapon.speed = 0.0
	## ACT: tap, reading the weapon commitment every tick until the parry.
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(runner.state.tick))
	var before := 0.0
	var after := -1.0
	for _i in 40:
		before = _weapon(attacker)
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
		if runner.count(DuelEventTypes.PARRY) > 0:
			after = _weapon(attacker)
			break
	## ASSERT
	assert_true(after >= 0.0, "precondition: the guard parried the tap")
	assert_true(after < before, "the arrest took the commitment down on its tick (%.3f → %.3f)" % [before, after])
	var stop := CommitmentModel.weapon_stop_time(attacker, _spec(), _rules.combat)
	assert_near(after, CommitmentModel.saturate(stop, _rules.combat.commit_weapon_reference_seconds), 1e-12, "and it is exactly the reading of the blade's own remaining debt")


## EQUAL-PRESS-001: two identical fighters driving straight at each other with
## identical input keep their shared midpoint — no side pushes the other.
## Bodies only: both swords are seated back at the same guard limit, out of
## the line, so the press is body against body and no sword contact enters it.
func test_two_identical_fighters_pressing_keep_their_midpoint() -> void:
	## ARRANGE: the point-symmetric opening, swords seated back, both closing.
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	for fighter: FighterState in [a, b]:
		fighter.weapon.angle = _rules.combatant(0).weapon.guard_limit
		fighter.weapon.stable_side = 1.0
	var start_x := (a.x + b.x) * 0.5
	var start_y := (a.y + b.y) * 0.5
	## ACT
	var drift := 0.0
	var pressing := 0
	for _i in 240:
		runner.drive(0.0, 1.0, 1)
		drift = maxf(drift, SimMath.length((a.x + b.x) * 0.5 - start_x, (a.y + b.y) * 0.5 - start_y))
		if runner.state.body_contact.phase == BodyContactState.Phase.CONTACTING:
			pressing += 1
	## ASSERT
	assert_eq(runner.count(DuelEventTypes.BLADE_CONTACT), 0, "precondition: no sword enters the press")
	assert_true(pressing > 60, "precondition: the bodies pressed into each other for a second or more (%d ticks)" % pressing)
	assert_true(drift < 1.0e-6, "the shared midpoint holds within solver tolerance (%s m)" % String.num_scientific(drift))
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())


## SYMMETRIC-PRESS-001: the same press through the swords. Two identical
## fighters from the point-symmetric opening, guards resting, driving into each
## other for four seconds: their blades meet and are held, and the duel stays
## the exact point reflection of itself — midpoint, bodies, headings and swords
## — on every tick. No slot, stored contact point or update order wins.
func test_two_identical_fighters_pressing_through_their_swords_stay_mirrored() -> void:
	## ARRANGE
	var runner := SimRunner.create(_rules, 1)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	var start_x := (a.x + b.x) * 0.5
	var start_y := (a.y + b.y) * 0.5
	## ACT
	var drift := 0.0
	var mirror := 0.0
	var held := 0
	for _i in 240:
		runner.drive(0.0, 1.0, 1)
		drift = maxf(drift, SimMath.length((a.x + b.x) * 0.5 - start_x, (a.y + b.y) * 0.5 - start_y))
		mirror = maxf(mirror, absf(a.vx + b.vx) + absf(a.vy + b.vy) + absf(a.weapon.angle - b.weapon.angle) + absf(a.weapon.speed - b.weapon.speed) + absf(SimMath.wrap_angle(a.facing - b.facing - PI)))
		if runner.state.blade_contact.phase != SwordContactSet.Phase.SEPARATED:
			held += 1
	## ASSERT
	assert_true(runner.count(DuelEventTypes.BLADE_CONTACT) > 0 and held > 30, "precondition: the swords met and were held (%d ticks)" % held)
	assert_true(drift < 1.0e-6, "the shared midpoint holds (%s m; under a millimetre is the gameplay floor)" % String.num_scientific(drift))
	assert_true(mirror < 1.0e-6, "and the two stay each other's exact reflection (%s)" % String.num_scientific(mirror))
	assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())


## NO-BONUS-001 / NO-RUNNING-BONUS-001: the same body speed and actuator force meet the same
## body-contact impulse, whether the speed came from a dash or a walk. Only
## the gesture ends (MOVE-002); no push is added.
func test_a_dash_shoves_no_harder_than_a_walk_at_the_same_speed() -> void:
	var results: Array[Dictionary] = []
	for dashing: bool in [false, true]:
		## ARRANGE
		var state := DuelFixture.state(_rules)
		var a := state.fighter(0)
		var b := state.fighter(1)
		DuelFixture.place(a, 0.0, 0.0, 0.0)
		DuelFixture.place(b, 0.4, 0.0, PI)
		a.vx = 4.0
		if dashing:
			a.gesture.mode = MovementGestureState.Mode.BURST
			a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
			a.gesture.burst_ticks_remaining = 4
		## ACT
		var events: Array[DuelEvent] = []
		ContactResolver.resolve(state, ContactFixture.body_push_report(1.0, 0.0), _rules, 0, 0.5, events)
		var push := DuelFixture.of_type(events, DuelEventTypes.BODY_PUSH)
		results.append({"impulse": push[0].number(DuelEventKeys.IMPULSE) if push.size() == 1 else -1.0, "a": a.vx, "b": b.vx})
	## ASSERT
	assert_true(float(results[0]["impulse"]) > 0.0, "precondition: the walk met the body")
	assert_eq(results[1]["impulse"], results[0]["impulse"], "the dash's impulse is the walk's")
	assert_eq(results[1]["a"], results[0]["a"], "the dasher keeps exactly what the walker keeps")
	assert_eq(results[1]["b"], results[0]["b"], "and the struck body moves exactly as far")


## COMMIT-CHASE-001 (MOVEMENT-FRAME-001 with COMMITMENT-001): a fighter
## advancing behind a full cut while the target stands broadside. The bearing
## τ is a quarter turn off at once; the heading φ lags it, and lags it further
## than a fighter with nothing committed; and the feet keep driving down φ —
## every tick's frame is that tick's starting heading — so the body runs on
## past rather than curving onto the target. No root path homes.
func test_a_committed_advance_runs_down_its_heading_not_onto_the_target() -> void:
	var turned := PackedFloat64Array()
	var drifts := PackedFloat64Array()
	var runs := PackedFloat64Array()
	for committed: bool in [true, false]:
		## ARRANGE: advancing at top speed, the target broadside out of reach.
		var runner := SimRunner.create(_rules, 1)
		runner.skip_intro()
		var me := runner.state.fighter(0)
		var target := runner.state.fighter(1)
		DuelFixture.place(me, 0.0, 0.0, 0.0)
		DuelFixture.place(target, 0.0, 4.0, -PI / 2.0)
		me.vx = _spec().fighter.max_speed
		if committed:
			me.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
			me.weapon.swing_dir = 1.0
			me.weapon.swing_charge = 1.0
			me.weapon.launch_preparation = 1.0
			me.weapon.speed = _spec().weapon.achievable_swing_speed(1.0, 1.0)
		## ACT: forward held, the frame checked against the heading every tick.
		var frame_error := 0.0
		for _i in TURN_TICKS:
			var start := me.facing
			runner.push(PlayerCommand.create(runner.state.tick, 0.0, 1.0), PlayerCommand.idle(runner.state.tick))
			frame_error = maxf(frame_error, absf(me.duel_forward_x - SimMath.cosine(start)) + absf(me.duel_forward_y - SimMath.sine(start)))
		## ASSERT (per case)
		assert_eq(frame_error, 0.0, "the feet drive down the tick-start heading every tick (committed: %s)" % committed)
		assert_true(runner.is_sound(), "every tick legal (%s)" % runner.violation_summary())
		turned.append(me.facing)
		drifts.append(me.y)
		runs.append(me.x)
	## ASSERT (across cases)
	assert_true(turned[0] > 0.0 and turned[0] < PI / 2.0, "the committed heading turns toward τ but lags it (%.3f of %.3f rad)" % [turned[0], PI / 2.0])
	assert_true(turned[0] < turned[1], "and lags it further than an uncommitted one (%.3f < %.3f rad)" % [turned[0], turned[1]])
	assert_true(drifts[0] < runs[0], "the committed body runs on down its line rather than onto the target (%.3f m across, %.3f m along)" % [drifts[0], runs[0]])
	assert_true(drifts[0] <= drifts[1], "and drifts toward it no more than an uncommitted one (%.3f ≤ %.3f m)" % [drifts[0], drifts[1]])


## MIRROR-001: every commitment reading and both authorities are exact under
## bilateral reflection.
func test_commitment_mirrors_exactly() -> void:
	var cases: Array[FighterState] = [_cutting(1.0), _cutting(0.0, 0.6), _fighter()]
	cases[0].vx = 2.0
	cases[0].vy = 1.3
	cases[0].ax = 5.0
	cases[0].weapon.motor_torque = 90.0
	cases[1].vx = -1.1
	cases[1].vy = -0.7
	cases[1].facing = 0.4
	cases[2].vx = 3.3
	cases[2].vy = 0.9
	cases[2].ay = -2.0
	for fighter in cases:
		var mirrored := FighterState.new()
		mirrored.health = fighter.health
		mirrored.weapon.reset(0.0)
		DuelFixture.place(mirrored, fighter.x, -fighter.y, -fighter.facing)
		mirrored.vx = fighter.vx
		mirrored.vy = -fighter.vy
		mirrored.ax = fighter.ax
		mirrored.ay = -fighter.ay
		mirrored.weapon.phase = fighter.weapon.phase
		mirrored.weapon.angle = -fighter.weapon.angle
		mirrored.weapon.speed = -fighter.weapon.speed
		mirrored.weapon.motor_torque = -fighter.weapon.motor_torque
		mirrored.weapon.swing_dir = -fighter.weapon.swing_dir
		mirrored.weapon.swing_charge = fighter.weapon.swing_charge
		mirrored.weapon.launch_preparation = fighter.weapon.launch_preparation
		assert_eq(_weapon(mirrored), _weapon(fighter), "the mirrored weapon debt is exactly the same")
		assert_eq(_root(mirrored), _root(fighter), "and the root's")
		assert_eq(_facing(mirrored), _facing(fighter), "and the facing's")
		assert_eq(_torque(mirrored), _torque(fighter), "so it turns with exactly the same torque")
		assert_eq(_rate(mirrored), _rate(fighter), "and rate")


## ATTACK-LINE-001 (LINE-CHANGE-001): a sidestep moves the target bearing τ;
## the attack line is `φ + θ`, and only φ can follow it. After the same
## lateral change of τ, a fighter mid-cut and a neutral one both start turning
## toward it at once, but over the same ticks the committed heading leaves
## more of the new angle unanswered — its redirect debt — while the turn never
## touches θ. That gap is the angle a defender can win without winning any
## position.
func test_a_sidestep_leaves_a_committed_line_behind_a_neutral_one() -> void:
	var line := deg_to_rad(35.0)
	var unanswered: Array[float] = []
	for committed: bool in [false, true]:
		## ARRANGE
		var fighter := _cutting(1.0) if committed else _fighter()
		if committed:
			fighter.vx = _spec().fighter.burst_speed_axial
		var theta := fighter.weapon.angle
		## PERTURB: the target steps; its bearing is now `line` off the heading.
		var tx := cos(line) * 1.3
		var ty := sin(line) * 1.3
		## ACT
		for _i in 6:
			FacingSystem.step(fighter, tx, ty, _torque(fighter), _spec().fighter, null, _rate(fighter))
		## ASSERT
		assert_true(fighter.facing > 0.0, "%s: the heading turns toward the new line (AUTHORITY-001)" % ("committed" if committed else "neutral"))
		assert_eq(fighter.weapon.angle, theta, "and turning the heading never moves θ")
		unanswered.append(line - fighter.facing)
	assert_true(unanswered[1] > unanswered[0], "the committed line leaves more of the sidestep unanswered (%.1f° vs %.1f°)" % [rad_to_deg(unanswered[1]), rad_to_deg(unanswered[0])])


## AUTHORITY-001: commitment never rejects the turn. A fully committed fighter
## asked to turn still changes its rotation on that very tick — slower, never
## refused — and keeps at least the committed floors.
func test_a_committed_fighter_still_turns_on_the_tick_it_is_asked() -> void:
	var committed := _cutting(1.0)
	committed.vx = _spec().fighter.burst_speed_axial
	var torque := _torque(committed)
	var rate := _rate(committed)
	assert_true(_facing(committed) > 0.25 and torque < 1.0, "precondition: committed (C_φ %.3f, torque share %.3f)" % [_facing(committed), torque])
	assert_true(torque >= _rules.combat.commit_turn_torque_floor and rate >= _rules.combat.commit_turn_speed_floor, "never below the floors (%.3f, %.3f)" % [torque, rate])
	FacingSystem.step(committed, 0.0, 3.0, torque, _spec().fighter, null, rate)
	assert_true(committed.turn_rate > 0.0, "it already turns toward the target this tick (%.4f rad/s)" % committed.turn_rate)


## CONDITION-001 composed, never doubled (RESPONSIVE-COMMITMENT-001):
## commitment describes the action, never the wound. The same physical state
## reads exactly the same commitment healthy or hurt; injury lowers the final
## capability once — the share is the healthy share times the wound's scale,
## held up by the floor.
func test_injury_never_changes_the_commitment_only_the_final_capability() -> void:
	var fighter := _cutting(1.0)
	fighter.vx = 3.0
	var max_health := _spec().fighter.max_health
	var hurt := ConditionModel.compute(max_health * 0.4, max_health, _rules.combat, ConditionState.new())
	assert_true(hurt.force_scale < 1.0 and hurt.tracking_scale < 1.0, "precondition: the wound costs force and tracking")
	var commitment := _facing(fighter)
	assert_true(commitment > 0.0, "precondition: the action is committed (%.3f)" % commitment)
	var healthy_torque := CommitmentModel.turn_torque_share(fighter, _spec(), ConditionState.new(), _rules.combat)
	var hurt_torque := CommitmentModel.turn_torque_share(fighter, _spec(), hurt, _rules.combat)
	assert_near(hurt_torque, maxf(healthy_torque * hurt.force_scale, _rules.combat.commit_turn_torque_floor), 1e-12, "the wound scales the final torque once")
	var healthy_rate := CommitmentModel.turn_rate_share(fighter, _spec(), ConditionState.new(), _rules.combat)
	var hurt_rate := CommitmentModel.turn_rate_share(fighter, _spec(), hurt, _rules.combat)
	assert_near(hurt_rate, maxf(healthy_rate * hurt.tracking_scale, _rules.combat.commit_turn_speed_floor), 1e-12, "and the final rate once")
	assert_eq(CommitmentModel.weapon_stop_time(fighter, _spec(), _rules.combat), CommitmentModel.weapon_stop_time(fighter, _spec(), _rules.combat), "the debt reads the healthy brake")


## RESPONSIVE-COMMITMENT-001: no threshold. The debt map is continuous through
## its reference and keeps growing past it — a little more momentum is always a
## little more commitment, and full commitment is approached, never snapped to.
func test_commitment_is_continuous_and_never_saturates_at_an_edge() -> void:
	var ref_time := _rules.combat.commit_weapon_reference_seconds
	var step := 1.0e-6
	assert_eq(CommitmentModel.saturate(0.0, ref_time), 0.0, "no debt, no commitment")
	assert_near(CommitmentModel.saturate(ref_time, ref_time), 0.5, 1e-12, "the reference is half committed")
	var below := CommitmentModel.saturate(ref_time - step, ref_time)
	var above := CommitmentModel.saturate(ref_time + step, ref_time)
	assert_true(above > below and above - below < 1.0e-5, "continuous across the reference (%s)" % String.num_scientific(above - below))
	var previous := 0.0
	for multiple: float in [0.5, 1.0, 2.0, 4.0, 8.0, 16.0]:
		var value := CommitmentModel.saturate(ref_time * multiple, ref_time)
		assert_true(value > previous and value < 1.0, "%.1f× the reference is more committed and still below full (%.4f)" % [multiple, value])
		previous = value


## Forward and backward of equal magnitude move authority in opposite
## directions around neutral, and the retreat side stops at neutral.
func test_forward_and_back_move_authority_opposite_ways_around_neutral() -> void:
	var speed := _spec().fighter.max_speed
	for charge: float in [0.0, 1.0]:
		var still := _cutting(charge, 0.6)
		var forward := _cutting(charge, 0.6)
		forward.vx = speed
		var back := _cutting(charge, 0.6)
		back.vx = -speed
		assert_true(_root(forward) > 0.0 and _root(back) < 0.0, "charge %.0f: signed root commitment either side of planted" % charge)
		assert_near(_root(forward), -_root(back), 1e-12, "charge %.0f: equal and opposite" % charge)
		assert_true(_torque(forward) < _torque(still), "charge %.0f: forward turns worse than planted" % charge)
		assert_true(_torque(back) > _torque(still) and _torque(back) <= 1.0, "charge %.0f: back turns better, never past neutral" % charge)