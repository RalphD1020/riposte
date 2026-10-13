extends TestCase

## CPU: same commands, same rules; difficulty is decision quality only
## (PLAN Phase 9). Results are deterministic per seed; the seed set is fixed.
##
## These are laws — a failure is a bug. Whether a sharper profile actually
## wins more is a balance claim and lives in CPU-BALANCE (`test_cpu_balance.gd`).
##
## Implements: /spec/invariants.md#cpu-001
## See also: /docs/concepts/cpu.md

const MAX_TICKS := 40000


func _init() -> void:
	suite_name = "CPU"


func _session(first: MatchConfig.Difficulty, second: MatchConfig.Difficulty, seed_value: int) -> MatchSession:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, seed_value)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, CpuProfile.for_difficulty(first), seed_value, 0),
		CpuController.create(config.rules, CpuProfile.for_difficulty(second), seed_value, 1),
	]
	return MatchSession.create(config, controllers)


func _play(session: MatchSession) -> MatchSession:
	while not session.is_finished() and session.state.tick < MAX_TICKS:
		session.step()
	return session


## Mean charge of the attacks a fighter actually committed to charging. Taps
## are deliberately excluded: a tap is 0% by definition, so counting them
## measures how often the CPU taps, not how heavily it charges.
func _mean_committed_charge(session: MatchSession, slot: int) -> float:
	var total := 0.0
	var count := 0
	for event in session.events:
		if event.actor != slot or event.type != DuelEventTypes.ATTACK_RELEASED:
			continue
		var charge := event.number(DuelEventKeys.CHARGE)
		if charge > 0.0:
			total += charge
			count += 1
	return 0.0 if count == 0 else total / float(count)


## ──────────────────────────────── MEASURE ─────────────────────────────────
##
## Profile distances are authored in metres at the reference duel's strike
## reach. Correcting the reference geometry must not silently rescale them.


## For the reference fighter and sword a profile metre is a metre; any other
## duel scales every preferred distance with its own strike reach (CPU-001).
func test_a_profile_metre_is_a_metre_for_the_reference_duel() -> void:
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	assert_near(CpuController.calibration_reach(), reach, 1e-12, "fixture: calibrated at the reference duel's own strike reach")
	var standard := CpuController.create(rules, CpuProfile.for_difficulty(MatchConfig.Difficulty.MEDIUM), 1, 0)
	assert_near(standard._range(1.0), 1.0, 1e-12, "the reference duel reads a profile metre literally")
	var longer := StandardDuelRules.create()
	longer.combatant(1).fighter.hurt_radius += 0.1
	assert_near(WeaponKinematics.strike_reach(longer.combatant(0), longer.combatant(1)), reach + 0.1, 1e-12, "perturbation: only the strike reach against a bigger target grew")
	var scaled := CpuController.create(longer, CpuProfile.for_difficulty(MatchConfig.Difficulty.MEDIUM), 1, 0)
	assert_near(scaled._range(1.0), (reach + 0.1) / reach, 1e-12, "a longer reach scales every preferred distance with it")


## ──────────────────────────────── FAIRNESS ────────────────────────────────
##
## Difficulty is cognition, never a better body. These are the claims a player
## is entitled to regardless of how the ladder is tuned.


## CPU-002. The airtight form of "difficulty never touches the physics": drive
## an identical command stream under each difficulty's configuration and the
## duel is bit-identical. Reading the profile for forbidden fields would prove
## only that today's fields are clean; this fails if difficulty reaches the
## rules by any route, including one nobody thought to look for.
func test_difficulty_never_reaches_the_physics() -> void:
	var hashes := PackedStringArray()
	var levels: Array[MatchConfig.Difficulty] = [MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.MEDIUM, MatchConfig.Difficulty.HARD]
	for level in levels:
		var config := MatchConfig.quick_play(level, 17)
		var runner := SimRunner.create(config.rules, config.seed_value)
		runner.skip_intro()
		## A stream that exercises the quantities difficulty could plausibly
		## cheat on: closing force, turning torque, a held charge, a release.
		for tick in 180:
			var hold := tick < 120
			runner.push(
				PlayerCommand.create(runner.state.tick, 0.4, 1.0, hold, tick == 120, false),
				PlayerCommand.create(runner.state.tick, -0.4, -1.0, false, false, false),
			)
		hashes.append(StateHasher.hash_state(runner.state))
	assert_eq(hashes.size(), 3, "fixture: every difficulty ran the same stream")
	assert_true(hashes[0].length() > 0, "fixture: the stream moved the state somewhere hashable")
	assert_eq(hashes[0], hashes[1], "Easy and Medium are the same body and sword")
	assert_eq(hashes[1], hashes[2], "and so is Hard")


## The other half of CPU-002: `DuelRules` is where every physical quantity
## lives, so difficulty must not be able to select a different one.
func test_every_difficulty_resolves_one_set_of_rules() -> void:
	var easy := MatchConfig.quick_play(MatchConfig.Difficulty.EASY, 23)
	var hard := MatchConfig.quick_play(MatchConfig.Difficulty.HARD, 23)
	assert_eq(easy.cpu_difficulty, MatchConfig.Difficulty.EASY, "fixture: the configs differ in difficulty")
	assert_eq(hard.cpu_difficulty, MatchConfig.Difficulty.HARD, "fixture: and the other way")
	assert_eq(easy.rules.version, hard.rules.version, "one rules version")
	assert_eq(easy.rules.combatant(0).fighter.mass, hard.rules.combatant(0).fighter.mass, "one body mass")
	assert_eq(easy.rules.combatant(0).fighter.max_speed, hard.rules.combatant(0).fighter.max_speed, "one movement cap")
	assert_eq(easy.rules.combatant(0).fighter.turn_speed_max, hard.rules.combatant(0).fighter.turn_speed_max, "one turn authority")
	assert_eq(easy.rules.combatant(0).weapon.mass, hard.rules.combatant(0).weapon.mass, "one sword mass")
	assert_eq(easy.rules.combatant(0).weapon.blade_length(), hard.rules.combatant(0).weapon.blade_length(), "one reach")
	assert_eq(easy.rules.combat.damage_values, hard.rules.combat.damage_values, "one damage curve")


## CPU-004. Every dial a profile owns, and the category that earns it a place.
## An allow-list rather than a list of banned physical words: the next
## physical quantity to be smuggled in is by definition one nobody thought to
## ban, and adding a field here is the moment to decide which it is.
const PROFILE_PERCEPTION: Array[String] = ["reaction_ticks", "range_error", "anticipation"]
const PROFILE_CADENCE: Array[String] = ["decision_ticks", "decision_jitter"]
const PROFILE_POLICY: Array[String] = [
	"difficulty",
	"engage_range", "tap_range", "charge_range", "release_slack", "release_any_range",
	"aggression", "retreat_weight", "spacing_weight", "angle_weight", "punish_weight",
	"intercept_weight", "bait_weight", "charge_weight", "probe_weight",
	"initiative_weight", "pressure_weight", "attack_threshold",
	"point_threat_weight", "burst_weight",
	"charge_min", "charge_max",
	"corner_pressure_weight", "tempo_awareness", "withdrawal_discipline",
	"lateral_dash_weight",
	"edge_exploit_weight",
]


func test_a_profile_may_only_own_perception_cadence_and_policy() -> void:
	var allowed: Array[String] = []
	allowed.append_array(PROFILE_PERCEPTION)
	allowed.append_array(PROFILE_CADENCE)
	allowed.append_array(PROFILE_POLICY)
	assert_eq(allowed.size(), PROFILE_PERCEPTION.size() + PROFILE_CADENCE.size() + PROFILE_POLICY.size(), "fixture: the categories are disjoint lists")
	var declared := 0
	for property: Dictionary in CpuProfile.new().get_property_list():
		var name: String = property["name"]
		## Script variables only; `get_property_list` also reports the engine's
		## own members and the script resource itself.
		if not (int(property["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		declared += 1
		assert_true(allowed.has(name), "profile field '%s' is declared as perception, cadence, or policy" % name)
	assert_eq(declared, allowed.size(), "every allowed field exists and none is missing (%d declared)" % declared)


## ─────────────────────────────── CORRECTNESS ───────────────────────────────
##
## The difficulty axes themselves: authored data and structural guarantees,
## independent of who wins. These hold regardless of balance.


## Starting distances, as multiples of the duel's own strike reach, so the law
## is read in the same combat situation whatever the geometry makes a metre.
const OVERCHARGE_SPACINGS: PackedFloat64Array = [1.0, 1.2, 1.4]
const OVERCHARGE_TICKS := 900


## The charge `profile` commits to from the same scene: an idle opponent
## `spacing` strike reaches away, both at guard, the same seed. Mean committed
## charge over its charged releases, and how many there were.
func _committed_from(profile: CpuProfile, spacing: float, seed_value: int) -> PackedFloat64Array:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, seed_value)
	runner.skip_intro()
	DuelFixture.place(runner.state.fighter(0), 0.0, 0.0, 0.0)
	DuelFixture.place(runner.state.fighter(1), spacing * WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)), 0.0, PI)
	var cpu := CpuController.create(rules, profile, seed_value, 0)
	for _i in OVERCHARGE_TICKS:
		runner.push(cpu.command_for(runner.state, 0), PlayerCommand.idle(runner.state.tick))
	var total := 0.0
	var count := 0
	for event in runner.events:
		if event.actor == 0 and event.type == DuelEventTypes.ATTACK_RELEASED and event.number(DuelEventKeys.CHARGE) > 0.0:
			total += event.number(DuelEventKeys.CHARGE)
			count += 1
	return PackedFloat64Array([total, float(count)])


## Hard wastes less time overcharging: put Easy and Hard in exactly the same
## situations — an idle opponent at the same multiples of the strike reach,
## the same seeds — and Hard commits to lighter charges. Read in reach, not
## metres, so a geometry change cannot move the situation out from under the
## law; how often each holds over whole duels is a balance reading
## (CPU-BALANCE), not this law.
func test_easy_overcharges_and_hard_stays_quick() -> void:
	var easy_profile := CpuProfile.easy()
	var hard_profile := CpuProfile.hard()
	assert_true(easy_profile.charge_min > hard_profile.charge_max, "Easy's lightest charge target is heavier than Hard's heaviest")
	var sums := {"easy": PackedFloat64Array([0.0, 0.0]), "hard": PackedFloat64Array([0.0, 0.0])}
	for spacing in OVERCHARGE_SPACINGS:
		for seed_value: int in [3, 7]:
			for key: String in sums:
				var got := _committed_from(easy_profile if key == "easy" else hard_profile, spacing, seed_value)
				var sum: PackedFloat64Array = sums[key]
				sum[0] += got[0]
				sum[1] += got[1]
				sums[key] = sum
	var easy: PackedFloat64Array = sums["easy"]
	var hard: PackedFloat64Array = sums["hard"]
	assert_true(easy[1] >= 3.0 and hard[1] >= 3.0, "precondition: both charged in these situations (Easy %d, Hard %d releases)" % [int(easy[1]), int(hard[1])])
	var easy_mean := easy[0] / maxf(easy[1], 1.0)
	var hard_mean := hard[0] / maxf(hard[1], 1.0)
	assert_true(easy_mean > hard_mean, "from the same situations Easy commits heavier charges than Hard (%.2f vs %.2f)" % [easy_mean, hard_mean])


func test_reading_state_never_changes_it() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 4)
	runner.skip_intro()
	var cpu := CpuController.create(rules, CpuProfile.hard(), 4, 1)
	var before := StateHasher.hash_state(runner.state)
	for _i in 30:
		cpu.command_for(runner.state, 1)
	assert_eq(StateHasher.hash_state(runner.state), before, "the CPU only observes")


func test_perception_lags_by_the_reaction_time() -> void:
	var session := _session(MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.HARD, 2)
	while session.state.round_ticks < 120 and not session.is_finished():
		session.step()
	var easy := session.controllers[0] as CpuController
	var hard := session.controllers[1] as CpuController
	assert_true(easy.last_perceived_tick >= 0 and hard.last_perceived_tick >= 0, "precondition: both decided")
	assert_true(session.state.tick - easy.last_perceived_tick >= easy.profile.reaction_ticks, "Easy sees the past")
	assert_true(session.state.tick - hard.last_perceived_tick >= hard.profile.reaction_ticks, "Hard sees the past too")
	assert_true(easy.profile.reaction_ticks > hard.profile.reaction_ticks, "Easy reacts slower")


## ───────────────────────── PERCEPTION AND GESTURE ─────────────────────────


## The CPU sees vulnerability, but only the kind a watching human sees: a
## physical reading of the opponent's body, delayed like everything else it
## perceives. It never receives a strike quality, because before contact
## nobody knows what a hit would do (COMBAT-009).
func test_the_cpu_reads_exposure_as_a_body_not_as_a_forecast() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(1)
	var them := state.fighter(0)
	## ARRANGE: drawn in symmetrically to 2 m, inside the threat horizon
	## (THREAT-001) — out of each other's reach both read even.
	var mx := (me.x + them.x) * 0.5
	var my := (me.y + them.y) * 0.5
	var apart := SimMath.length(me.x - them.x, me.y - them.y)
	for fighter: FighterState in [me, them]:
		fighter.x = mx + (fighter.x - mx) * 2.0 / apart
		fighter.y = my + (fighter.y - my) * 2.0 / apart
	var horizon := float(InitiativeModel.HORIZON_TICKS) * SimulationTimebase.TICK_SECONDS
	assert_true(InitiativeModel.time_to_threat(me, them, rules) < horizon, "fixture: a ready fighter threatens inside the horizon")
	var composed := CpuObservation.observe(state, 1, rules)
	## Exactly the reading the player's own HUD is given for this fighter.
	assert_eq(composed.opp_exposure, ExposureModel.reading(them, me, rules), "the same exposure the snapshot projects")
	assert_between(composed.opp_exposure, 0.0, 1.0, "as a bounded fraction")
	them.weapon.set_phase(CombatPhase.Id.OVERSWING)
	them.weapon.commitment = 1.0
	them.stability = 0.2
	var flailing := CpuObservation.observe(state, 1, rules)
	assert_true(flailing.opp_exposure > composed.opp_exposure, "a committed, unbalanced opponent reads as more exposed")
	## And nothing resembling a resolved strike is anywhere on the record.
	var keys := PackedStringArray([DuelEventKeys.QUALITY, DuelEventKeys.PHYSICAL_QUALITY, DuelEventKeys.SEVERITY, DuelEventKeys.GRADE, DuelEventKeys.SWING_POTENTIAL])
	for key in keys:
		assert_false(key in flailing, "no pre-contact strike quality reaches the CPU: %s" % key)


func test_the_cpu_perceives_point_threats() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var them := state.fighter(0)
	them.weapon.angle = 0.0
	them.vx = 0.0
	them.vy = 0.0
	var composed := CpuObservation.observe(state, 1, rules)
	var base_threat := composed.opp_point_threat
	## Close along the facing direction (toward the opponent).
	them.vx = cos(them.facing) * rules.combatant(0).fighter.max_speed * 0.8
	them.vy = sin(them.facing) * rules.combatant(0).fighter.max_speed * 0.8
	var closing := CpuObservation.observe(state, 1, rules)
	assert_true(closing.opp_point_threat > base_threat, "closing velocity increases point threat")
	them.vx = 0.0
	them.vy = 0.0
	them.weapon.angle = PI * 0.5
	var sideways := CpuObservation.observe(state, 1, rules)
	assert_true(sideways.opp_point_threat < base_threat, "a perpendicular blade is not a point threat")


## THREAT-001 cost: a decision reads an observation `reaction_ticks` old, so
## the costly readings are taken only when one is read — from the bodies as
## they stood then. An observation recorded mid-exchange and resolved after
## the duel has moved on reads exactly what an observation taken whole at that
## tick reads, to the bit.
func test_a_recorded_observation_resolves_to_what_was_seen_then() -> void:
	## ARRANGE: a live exchange, both fighters moving and swinging.
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	runner.drive(0.0, 1.0, 40)
	runner.push(PlayerCommand.create(runner.state.tick, 0.3, 1.0, true, true), PlayerCommand.create(runner.state.tick, -0.2, 1.0, true))
	runner.drive(0.0, 1.0, 3)
	var whole := CpuObservation.observe(runner.state, 1, rules)
	var recorded := CpuObservation.record(runner.state, 1, rules)
	assert_true(whole.my_threat_time > 0.0 and whole.opp_threat_time > 0.0, "fixture: both sides read a threat time")
	## PERTURB: the duel moves on before the observation is read.
	runner.drive(1.0, -1.0, 25)
	assert_ne(runner.state.fighter(0).x, recorded.opp_x, "fixture: the live bodies have moved")
	## ACT
	recorded.resolve(rules)
	## ASSERT
	assert_eq(recorded.my_threat_time, whole.my_threat_time, "my threat time is the one seen then")
	assert_eq(recorded.opp_threat_time, whole.opp_threat_time, "the opponent's too")
	assert_eq(recorded.my_threat.residual_gap, whole.my_threat.residual_gap, "and what was left of each prediction")
	assert_eq(recorded.opp_threat.readiness_remaining, whole.opp_threat.readiness_remaining, "readiness still owed")
	assert_eq(recorded.opp_exposure, whole.opp_exposure, "the exposure read from them")
	assert_eq(recorded.opp_opening, whole.opp_opening, "and the opening")


func test_the_cpu_perceives_opponent_condition() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var seen := CpuObservation.observe(state, 1, rules)
	assert_eq(seen.opp_condition, FighterCondition.Id.HEALTHY, "full health reads HEALTHY")
	state.fighter(0).health = rules.combatant(0).fighter.max_health * 0.2
	var hurt := CpuObservation.observe(state, 1, rules)
	assert_eq(hurt.opp_condition, FighterCondition.Id.CRITICAL, "20% health reads CRITICAL")


## A dash is typed, not called. Hard must reach a burst through the same
## `DirectionalTapRecognizer` a thumb drives, which is what guarantees it
## cannot reach a movement state a player cannot.
func test_the_cpu_dashes_by_typing_the_gesture() -> void:
	var dashes := 0
	for seed_value in PackedInt32Array([3, 5, 9, 11]):
		for event in _play(_session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.HARD, seed_value)).events:
			if event.type == DuelEventTypes.BURST_STARTED:
				dashes += 1
	assert_true(dashes > 0, "Hard commits dashes over the ladder seeds")
	## And the dashes are *entirely* in the commands. Replaying the recorded
	## stream with no CPU present at all reproduces every one of them, which
	## is only possible if the controller reached the burst the same way a
	## thumb does. A private dash call would vanish on replay.
	var session := _play(_session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.HARD, 3))
	var live := 0
	for event in session.events:
		if event.type == DuelEventTypes.BURST_STARTED:
			live += 1
	assert_true(live > 0, "precondition: seed 3 contained dashes")
	assert_eq(ReplayVerifier.verify(session.record, session.config.rules), ReplayVerifier.VERIFIED, "the recorded commands reproduce the duel exactly")


## Easy has no gesture skill, and that is a legitimate difficulty axis because
## it costs Easy nothing it is entitled to — the dash is available to it, it
## simply never types one.
func test_easy_never_dashes_and_hard_does() -> void:
	assert_eq(CpuProfile.easy().burst_weight, 0.0, "Easy does not use the gesture")
	assert_true(CpuProfile.hard().burst_weight > CpuProfile.medium().burst_weight, "and sharper profiles use it more")
	var easy_dashes := 0
	for seed_value in PackedInt32Array([3, 5, 9, 11]):
		for event in _play(_session(MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.EASY, seed_value)).events:
			if event.type == DuelEventTypes.BURST_STARTED:
				easy_dashes += 1
	assert_eq(easy_dashes, 0, "so an all-Easy duel contains no dashes at all")


## Charge is displacement, not duration. A CPU holding for a target it has not
## physically earned must keep holding, however many ticks pass — otherwise it
## would be releasing on a clock the player does not have.
func test_the_cpu_holds_for_travel_rather_than_for_ticks() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 7)
	runner.skip_intro()
	var cpu := CpuController.create(rules, CpuProfile.medium(), 7, 0)
	var weapon := runner.state.fighter(0).weapon
	var charging := 0
	## Long enough to see several charges against an idle opponent; the law is
	## per release, so the window only has to contain one.
	for _i in 900:
		var command := cpu.command_for(runner.state, 0)
		if weapon.phase == CombatPhase.Id.CHARGING:
			charging += 1
			if command.attack_released:
				## Every release the CPU makes out of a wind-back is made
				## against earned travel, never against a tick count.
				assert_true(weapon.charge > 0.0, "it had actually wound the blade back")
		runner.push(command, PlayerCommand.idle(runner.state.tick))
	assert_true(charging > 0, "precondition: the CPU charged at least once")


func test_cpu_play_is_reproducible_and_well_formed() -> void:
	var first := _play(_session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.EASY, 9))
	var second := _play(_session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.EASY, 9))
	assert_eq(first.record.final_hash, second.record.final_hash, "same seed, same CPU duel")
	var out_of_range := 0
	for stream: PackedInt32Array in [first.record.commands_0, first.record.commands_1]:
		for index in range(0, stream.size(), PlayerCommand.PACKED_STRIDE):
			if absi(stream[index + 1]) > PlayerCommand.AXIS_MAX or absi(stream[index + 2]) > PlayerCommand.AXIS_MAX:
				out_of_range += 1
	assert_eq(out_of_range, 0, "every CPU command is a legal PlayerCommand")


## ──────────────────────── TACTICAL ASSESSMENT ─────────────────────────────


func test_assessment_is_pure_and_compact() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var before := StateHasher.hash_state(state)
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.medium())
	assert_eq(StateHasher.hash_state(state), before, "assessment does not mutate state")
	assert_eq(assessment.burst_scores.size(), TacticalAssessment.BURST_COUNT, "4 burst scores")
	assert_between(assessment.measure_quality, 0.0, 1.0, "measure quality is bounded")
	assert_between(assessment.line_advantage, 0.0, 1.0, "line advantage is bounded")
	assert_between(assessment.tempo_opportunity, 0.0, 1.0, "tempo is bounded")
	assert_between(assessment.withdrawal_urge, 0.0, 1.0, "withdrawal is bounded")


func test_assessment_reads_tempo_from_recovery() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var them := state.fighter(1)
	them.weapon.set_phase(CombatPhase.Id.RECOVERY)
	them.weapon.recovery_left = 20
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, state.fighter(0), 1.5, reach, rules, CpuProfile.hard())
	assert_true(assessment.tempo_opportunity > 0.0, "opponent in recovery reads as a tempo opportunity")


func test_assessment_reads_arena_pressure() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	state.fighter(0).x = 0.0
	state.fighter(0).y = 0.0
	state.fighter(1).x = rules.platform_radius * 0.8
	state.fighter(1).y = 0.0
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, state.fighter(0), 5.0, reach, rules, CpuProfile.hard())
	assert_true(assessment.arena_pressure > 0.0, "opponent near edge reads as positive arena pressure")


## ──────────────────── ALL FOUR BURSTS (CPU-004) ──────────────────────────


func test_lateral_dashes_are_available_to_all_difficulties() -> void:
	var medium := CpuProfile.medium()
	var hard := CpuProfile.hard()
	## Easy may have zero lateral weight — that is a profile decision, not a
	## missing action. The action vocabulary exists for all.
	assert_true(hard.lateral_dash_weight > 0.0, "Hard uses lateral dashes")
	assert_true(medium.lateral_dash_weight >= 0.0, "Medium's lateral weight is authored (may be low)")
	assert_true(hard.lateral_dash_weight >= medium.lateral_dash_weight, "Hard at least as lateral as Medium")


## ──────────────── STAMINA IS NOT A CPU SIGNAL (STAMINA-002) ────────────────


## Stamina is a deprecated resource with no gameplay consumer: the CPU must
## not read it, so draining it changes nothing the assessment says.
func test_stamina_never_changes_the_tactical_assessment() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var fresh := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.hard())
	assert_eq(me.stamina, rules.combatant(0).fighter.base_stamina, "arrange: full stamina")
	me.stamina = 0.0
	assert_eq(me.stamina, 0.0, "perturb: stamina emptied")
	var drained := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.hard())
	assert_eq(drained.burst_scores, fresh.burst_scores, "burst utilities ignore stamina")
	assert_eq(drained.withdrawal_urge, fresh.withdrawal_urge, "withdrawal ignores stamina")
	assert_false("stamina_depletion" in drained, "the assessment carries no stamina reading")
	assert_false("stamina_cost_weight" in CpuProfile.hard(), "no profile weighs stamina")

## ──────────────────────── DECISION TRACE (Phase 8a) ───────────────────────


func test_trace_has_fixed_typed_fields() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.medium())
	var utilities := PackedFloat64Array([0.15, 0.5, 0.2, 0.1, 0.05])
	var trace := CpuDecisionTrace.create(42, 40, utilities, CpuController.Move.APPROACH, CpuController.Attack.TAP, assessment)
	assert_eq(trace.tick, 42, "decision tick")
	assert_eq(trace.observation_tick, 40, "observation tick")
	assert_eq(trace.move_scores.size(), CpuDecisionTrace.MOVE_COUNT, "5 move scores")
	assert_eq(trace.chosen_move, CpuController.Move.APPROACH, "chosen move")
	assert_eq(trace.chosen_attack, CpuController.Attack.TAP, "chosen attack")
	assert_between(trace.measure_quality, 0.0, 1.0, "measure quality from assessment")
	assert_eq(trace.burst_started, false, "no burst by default")
	assert_eq(trace.burst_is_lateral, false, "not lateral by default")


func test_trace_utilities_are_independent_copies() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, state.fighter(0), 1.5, reach, rules, CpuProfile.medium())
	var utilities := PackedFloat64Array([0.15, 0.8, 0.2, 0.1, 0.05])
	var trace := CpuDecisionTrace.create(10, 8, utilities, CpuController.Move.APPROACH, CpuController.Attack.NONE, assessment)
	utilities[1] = 99.0
	assert_eq(trace.move_scores[1], 0.8, "modifying source does not change trace (independent copy)")


## Hard's last approach score `spacing` metres from an idle opponent at the
## arena centre while its own body moves toward them at `speed` (held each
## tick: the scene is frozen and only the tick advances).
func _approach_score(spacing: float, speed: float) -> float:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var state := runner.state
	DuelFixture.place(state.fighter(0), -spacing * 0.5, 0.0, 0.0)
	DuelFixture.place(state.fighter(1), spacing * 0.5, 0.0, PI)
	var cpu := CpuController.create(rules, CpuProfile.hard(), 3, 0)
	for _i in 40:
		state.tick += 1
		state.fighter(0).vx = speed
		cpu.command_for(state, 0)
	return cpu.traces[cpu.traces.size() - 1].move_scores[CpuController.Move.APPROACH]


## Measure is judged where the bodies will be once an approach can be stopped
## (7B.8): the same distance that still calls a standing CPU in stops calling
## one already closing fast, because its stride will carry it the rest of the
## way — two fighters judged on distance alone overshoot into each other's
## hilts.
func test_an_approach_counts_its_own_stopping_distance() -> void:
	var rules := DuelFixture.rules()
	var hard := CpuProfile.hard()
	var spacing := 1.7
	var speed := 4.0
	var desired := hard.tap_range * WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)) / CpuController.calibration_reach() + CpuController.READY_RANGE_LEAD
	var lead := speed * float(hard.decision_ticks) * SimulationTimebase.TICK_SECONDS + speed * speed / (2.0 * rules.combatant(0).fighter.brake_accel())
	assert_true(spacing - hard.range_error > desired, "fixture: standing, the opponent is outside Hard's measure (%.2f > %.2f m)" % [spacing, desired])
	assert_true(spacing + hard.range_error - lead < desired, "fixture: closing at %.1f m/s it would arrive inside it (lead %.2f m)" % [speed, lead])
	var standing := _approach_score(spacing, 0.0)
	assert_true(standing > 0.0, "standing outside its measure, Hard steps in (%.2f)" % standing)
	## Perturb: the same distance, already closing fast.
	assert_eq(_approach_score(spacing, speed), 0.0, "closing that fast, its stride already reaches the measure: no more approach")


func test_cpu_controller_accumulates_traces() -> void:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 7)
	runner.skip_intro()
	var cpu := CpuController.create(rules, CpuProfile.hard(), 7, 1)
	assert_eq(cpu.traces.size(), 0, "no traces before first decision")
	for _i in 60:
		runner.push(PlayerCommand.idle(runner.state.tick), cpu.command_for(runner.state, 1))
	assert_true(cpu.traces.size() > 0, "traces accumulated after stepping")
	var first := cpu.traces[0]
	assert_true(first.tick >= 0, "trace has a valid tick")
	assert_eq(first.move_scores.size(), CpuDecisionTrace.MOVE_COUNT, "trace has 5 move scores")
	assert_true(first.observation_tick <= first.tick, "observation is not from the future")


func test_traces_cleared_between_rounds() -> void:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.HARD, 5)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, CpuProfile.hard(), 5, 0),
		CpuController.create(config.rules, CpuProfile.hard(), 5, 1),
	]
	var session := MatchSession.create(config, controllers)
	while session.state.round_ticks < 60 and not session.is_finished():
		session.step()
	var cpu := controllers[1] as CpuController
	assert_true(cpu.traces.size() > 0, "precondition: traces exist during round")
	## Round transition resets via _forget.
	while session.state.phase == MatchPhase.Id.ROUND_ACTIVE and not session.is_finished():
		session.step()
	## After round ends, next step clears traces.
	if not session.is_finished():
		session.step()
		assert_eq(cpu.traces.size(), 0, "traces cleared on round boundary")


## ────────────────── PUSH-PRESSURE AWARENESS (CPU-007) ─────────────────────
##
## The CPU reads the solved constraint impulse, not the opponent's hidden
## motor intent. Hard uses better prediction, not faster reaction.


func test_push_assessment_inactive_when_separated() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.hard())
	assert_false(assessment.body_contact_active, "no body contact when SEPARATED")
	assert_eq(assessment.push_pressure, 0.0, "zero push pressure when SEPARATED")
	assert_false(assessment.being_displaced, "not displaced when SEPARATED")
	assert_eq(assessment.time_to_support_loss, 2147483647, "infinite time to support loss when SEPARATED")


func test_push_assessment_reads_solved_impulse() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	## Place CPU at positive x near the edge, facing inward.
	DuelFixture.place(me, rules.platform_radius * 0.7, 0.0, PI)
	var bc := state.body_contact
	bc.begin_contact()
	bc.tick()
	## Normal from fighter 0→1 points inward; fighter 0 receives −n = outward.
	bc.last_constraint_impulse = 200.0
	bc.last_constraint_normal_x = -1.0
	bc.last_constraint_normal_y = 0.0
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.hard(), bc)
	assert_true(assessment.body_contact_active, "body contact active during CONTACTING")
	assert_true(assessment.push_pressure > 0.0, "positive push pressure when pushed outward")


func test_push_assessment_inward_push_is_not_displacement() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	## Place CPU at positive x, push inward.
	## Normal from fighter 0→1 points outward; fighter 0 receives −n = inward.
	DuelFixture.place(me, rules.platform_radius * 0.7, 0.0, PI)
	var bc := state.body_contact
	bc.begin_contact()
	bc.tick()
	bc.last_constraint_impulse = 200.0
	bc.last_constraint_normal_x = 1.0
	bc.last_constraint_normal_y = 0.0
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.hard(), bc)
	assert_true(assessment.body_contact_active, "contact is active")
	assert_true(assessment.push_pressure < 0.0, "negative push pressure = pushed toward center")
	assert_false(assessment.being_displaced, "inward push does not displace")


func test_push_time_to_support_loss_finite_when_displaced() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	## Place CPU near the edge.
	DuelFixture.place(me, rules.platform_radius * 0.9, 0.0, PI)
	var bc := state.body_contact
	bc.begin_contact()
	bc.tick()
	## Normal from fighter 0→1 points inward; fighter 0 receives −n = outward.
	bc.last_constraint_impulse = 2000.0
	bc.last_constraint_normal_x = -1.0
	bc.last_constraint_normal_y = 0.0
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.hard(), bc)
	assert_true(assessment.being_displaced, "strong outward push = displaced")
	assert_true(assessment.time_to_support_loss < 2147483647, "finite time to support loss")
	assert_true(assessment.time_to_support_loss >= 0, "time to support loss is non-negative")


func test_push_trace_captures_fields() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	DuelFixture.place(me, rules.platform_radius * 0.7, 0.0, PI)
	var bc := state.body_contact
	bc.begin_contact()
	bc.tick()
	bc.last_constraint_impulse = 200.0
	bc.last_constraint_normal_x = -1.0
	bc.last_constraint_normal_y = 0.0
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.hard(), bc)
	var utilities := PackedFloat64Array([0.1, 0.5, 0.2, 0.1, 0.05])
	var trace := CpuDecisionTrace.create(42, 40, utilities, CpuController.Move.RETREAT, CpuController.Attack.NONE, assessment)
	assert_true(trace.body_contact_active, "trace captures body contact active")
	assert_true(trace.push_pressure > 0.0, "trace captures push pressure")


func test_constraint_impulse_stored_on_body_contact_state() -> void:
	var state := DuelFixture.state(DuelFixture.rules())
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.4, 0.0, PI)
	a.vx = 5.0
	b.vx = 0.0
	state.body_contact.begin_contact()
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, DuelFixture.rules(), 0, 0.5, events)
	assert_true(state.body_contact.last_constraint_impulse > 0.0, "resolver stores solved impulse")
	assert_near(SimMath.length(state.body_contact.last_constraint_normal_x, state.body_contact.last_constraint_normal_y), 1.0, 1e-6, "stored normal is unit length")


func test_constraint_impulse_reset_between_rounds() -> void:
	var bc := BodyContactState.new()
	bc.begin_contact()
	bc.last_constraint_impulse = 100.0
	bc.last_constraint_normal_x = 1.0
	bc.reset()
	assert_eq(bc.last_constraint_impulse, 0.0, "reset clears impulse")
	assert_eq(bc.last_constraint_normal_x, 0.0, "reset clears normal x")
	assert_eq(bc.last_constraint_normal_y, 0.0, "reset clears normal y")


func test_push_pressure_from_physics_not_motor_intent() -> void:
	## The CPU's push_pressure derives from J_constraint/dt — the solved
	## impulse the contact resolver applied — not from the opponent's input
	## or motor force. This verifies the signal chain:
	## resolver → body_contact_state.last_constraint_impulse → assessment.push_pressure.
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	## CPU at positive x, opponent at origin, closing.
	DuelFixture.place(a, rules.platform_radius * 0.5, 0.0, PI)
	DuelFixture.place(b, rules.platform_radius * 0.5 - 0.4, 0.0, 0.0)
	a.vx = 0.0
	b.vx = 5.0
	state.body_contact.begin_contact()
	var report := ContactFixture.body_push_report(1.0, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, rules, 0, 0.5, events)
	## Now read what the CPU assessment sees.
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, a, 1.5, reach, rules, CpuProfile.hard(), state.body_contact)
	assert_true(assessment.body_contact_active, "contact active after resolver ran")
	assert_true(assessment.push_pressure > 0.0, "push pressure from the solved impulse, not motor intent")

