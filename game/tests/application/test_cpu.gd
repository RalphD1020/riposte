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
	"capitalize_margin",
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


## DASH-HYGIENE (CPU-008): a dash is a decision. With the CPU's own gesture
## state holding a first tap and a genuine rest, a full forward step would be
## the second tap — the real recognizer fires a forward dash for it (control).
## The CPU eases that step under the sector-entry deflection, inside the range
## a human stick can give, and the same recognizer then fires nothing.
func test_the_cpu_never_types_a_dash_it_did_not_decide_on() -> void:
	## ARRANGE: a first forward tap, then a rest.
	var rules := DuelFixture.rules()
	var body := rules.combatant(0).fighter
	var me := FighterState.new()
	for tick in 3:
		DirectionalTapRecognizer.observe(me.gesture, 0.0, 1.0, tick, body)
	for tick in range(3, 6):
		DirectionalTapRecognizer.observe(me.gesture, 0.0, 0.0, tick, body)
	var control := MovementGestureState.new()
	StateFork.copy(me.gesture, control)
	## ACT
	var cpu := CpuController.create(rules, CpuProfile.easy(), 3, 0)
	var eased := cpu._without_accidental_dash(PackedFloat64Array([0.0, 1.0]), 6, me)
	var command := PlayerCommand.create(6, eased[0], eased[1])
	## ASSERT
	assert_eq(DirectionalTapRecognizer.observe(control, 0.0, 1.0, 6, body), MovementGestureState.BurstKind.FORWARD_DASH, "control: the un-eased step is a second tap — a dash")
	var magnitude := SimMath.length(eased[0], eased[1])
	assert_true(magnitude <= 1.0 and magnitude < body.burst_enter_deflection, "the eased step stays a legal stick deflection under the sector entry (%.3f)" % magnitude)
	assert_true(SimMath.length(command.axis_x(), command.axis_y()) <= 1.0, "and so does the command it becomes")
	assert_eq(DirectionalTapRecognizer.observe(me.gesture, command.axis_x(), command.axis_y(), 6, body), MovementGestureState.BurstKind.NONE, "the same recognizer fires no dash for it")
	assert_true(eased[1] > 0.0, "and it still walks forward")


## CPU-PROPRIOCEPTION-001 (CPU-001): the CPU feels itself now and sees the
## opponent late. One observation, recorded at a tick; the duel moves on. Handed
## two different current selves, its threat readings follow the self at once;
## the opponent it reads is still the one recorded, whatever the opponent has
## done since.
func test_the_cpu_feels_itself_now_and_sees_the_opponent_late() -> void:
	## ARRANGE: a recorded observation, then the duel moves on.
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	runner.drive(0.0, 1.0, 30)
	var recorded := CpuObservation.record(runner.state, 1, rules)
	var seen_x := recorded.opp_x
	runner.drive(1.0, 0.0, 12)
	var opponent := runner.state.fighter(0)
	assert_ne(opponent.x, seen_x, "fixture: the opponent has moved since it was seen")
	## PERTURB: two current selves, half a metre apart.
	var near := FighterState.new()
	CpuObservation._copy(runner.state.fighter(1), near)
	var far := FighterState.new()
	CpuObservation._copy(near, far)
	var away := Vector2(far.x - seen_x, far.y - recorded.opp_y).normalized() * 0.5
	far.x += away.x
	far.y += away.y
	## ACT
	recorded.feel_self(near)
	recorded.resolve(rules)
	var near_threat := recorded.my_threat_time
	var near_hit := recorded.my_threat.residual_gap
	recorded.feel_self(far)
	recorded.resolve(rules)
	## ASSERT
	assert_true(recorded.my_threat_time != near_threat or recorded.my_threat.residual_gap != near_hit, "the self it reads is the current one: half a metre back changes its threat (%.3f / %.3f s)" % [near_threat, recorded.my_threat_time])
	assert_eq(recorded.opp_x, seen_x, "the opponent it reads is still the one seen through the delay")


## CPU-PROPRIOCEPTION-001, the point (B12): whether the opponent's point is aimed
## at the CPU is judged from the delayed opponent against the CPU's body as it
## is now. One recorded observation of an opponent closing with its point
## forward; handed the CPU's current self on that line it reads a point
## threat, handed the same self stepped well off the line it reads less.
func test_the_point_threat_is_read_against_the_cpus_current_body() -> void:
	## ARRANGE: the opponent's point straight at the CPU, closing.
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules)
	var them := state.fighter(0)
	them.weapon.angle = 0.0
	them.vx = cos(them.facing) * rules.combatant(0).fighter.max_speed * 0.8
	them.vy = sin(them.facing) * rules.combatant(0).fighter.max_speed * 0.8
	var recorded := CpuObservation.record(state, 1, rules)
	var on_line := FighterState.new()
	CpuObservation._copy(state.fighter(1), on_line)
	## PERTURB: the same self, a metre and a half off the opponent's line.
	var off_line := FighterState.new()
	CpuObservation._copy(on_line, off_line)
	off_line.x += -sin(them.facing) * 1.5
	off_line.y += cos(them.facing) * 1.5
	## ACT
	recorded.feel_self(on_line)
	recorded.resolve(rules)
	var aimed := recorded.opp_point_threat
	recorded.feel_self(off_line)
	recorded.resolve(rules)
	## ASSERT
	assert_true(aimed > 0.3, "fixture: on its line the opponent's point is a threat (%.3f)" % aimed)
	assert_true(recorded.opp_point_threat < aimed, "off the line, the same point is less of one (%.3f) — read against where the CPU is now" % recorded.opp_point_threat)


## CPU-MIRROR-001 (AI-FAIRNESS-001): the CPU has no slot. The same profile
## on the same seed, once in slot 0 of a duel and once in slot 1 of that duel's
## point reflection (positions and velocities reflected, headings turned half
## a revolution, the opponent standing idle in the other slot), issues the
## same frame-relative commands tick by tick and scores the same decisions.
## Only the starting state is built by hand; the observations, the decisions
## and the commands come through the ordinary state → observation → decision
## path. Each slot's random stream is its own by design, so the profile's
## random draws are pinned (no range error, no jitter, one charge target,
## certain dashes) — what is left is everything a slot could leak through.
func test_the_cpu_plays_the_mirrored_duel_from_the_other_slot_identically() -> void:
	## ARRANGE: a duel and its point reflection with the slots swapped.
	var rules := DuelFixture.rules()
	var profile := CpuProfile.hard()
	profile.range_error = 0.0
	profile.decision_jitter = 0
	profile.charge_min = profile.charge_max
	profile.burst_weight = 1.0
	profile.lateral_dash_weight = 1.0
	var left := SimRunner.create(rules, 4)
	var right := SimRunner.create(rules, 4)
	left.skip_intro()
	right.skip_intro()
	var placements := [[0.3, -1.2, 1.4, 0.4, 1.1], [-0.2, 0.9, -1.6, -0.3, -0.5]]
	for slot in 2:
		var spot: Array = placements[slot]
		var mine := left.state.fighter(slot)
		var reflected := right.state.fighter(1 - slot)
		DuelFixture.place(mine, spot[0], spot[1], spot[2])
		DuelFixture.place(reflected, -float(spot[0]), -float(spot[1]), float(spot[2]) + PI)
		mine.vx = spot[3]
		mine.vy = spot[4]
		reflected.vx = -float(spot[3])
		reflected.vy = -float(spot[4])
	var cpu_left := CpuController.create(rules, profile, 4, 0)
	var cpu_right := CpuController.create(rules, profile, 4, 1)
	## ACT: the CPU drives slot 0 on the left and slot 1 on the right.
	var mismatches := 0
	var moved := 0
	var attacks := 0
	for _i in 300:
		if left.state.phase != MatchPhase.Id.ROUND_ACTIVE or right.state.phase != MatchPhase.Id.ROUND_ACTIVE:
			break
		var from_left := cpu_left.command_for(left.state, 0)
		var from_right := cpu_right.command_for(right.state, 1)
		if from_left.move_x != from_right.move_x or from_left.move_y != from_right.move_y or from_left.attack_pressed != from_right.attack_pressed or from_left.attack_released != from_right.attack_released or from_left.dash_modifier != from_right.dash_modifier:
			mismatches += 1
		if from_left.move_x != 0.0 or from_left.move_y != 0.0:
			moved += 1
		if from_left.attack_pressed:
			attacks += 1
		left.push(from_left, PlayerCommand.idle(left.state.tick))
		right.push(PlayerCommand.idle(right.state.tick), from_right)
	## ASSERT
	assert_true(cpu_left.traces.size() >= 4, "fixture: the CPU recorded whole decisions (%d; a decision while holding or recovering is not traced)" % cpu_left.traces.size())
	assert_true(moved > 0 and attacks > 0, "fixture: and acted — footwork and attacks, not an idle stream (%d moving commands, %d attack presses)" % [moved, attacks])
	assert_eq(mismatches, 0, "every command from the other slot is the same frame-relative command")
	assert_eq(cpu_right.traces.size(), cpu_left.traces.size(), "the same number of decisions")
	for i in mini(cpu_left.traces.size(), cpu_right.traces.size()):
		var a := cpu_left.traces[i]
		var b := cpu_right.traces[i]
		assert_eq(b.chosen_move, a.chosen_move, "decision %d chooses the same footwork" % i)
		assert_eq(b.chosen_attack, a.chosen_attack, "decision %d the same attack" % i)
		for k in a.move_scores.size():
			assert_near(b.move_scores[k], a.move_scores[k], 1e-9, "decision %d scores move %d the same" % [i, k])


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


func test_a_closed_edge_does_not_score_the_rim_as_a_cliff() -> void:
	var rules := StandardDuelRules.pit()
	var state := DuelFixture.state(rules)
	var me := state.fighter(0)
	me.x = rules.platform_radius - 0.2
	me.vx = 5.0
	var seen := CpuObservation.observe(state, 0, rules)
	var reach := rules.combatant(0).weapon.tip_radius + rules.combatant(0).fighter.push_radius
	var assessment := TacticalAssessment.evaluate(seen, me, 1.5, reach, rules, CpuProfile.medium())
	assert_eq(assessment.arena_pressure, 0.0, "a closed edge has no arena pressure")
	assert_near(assessment.edge_clearance, rules.platform_radius, 1e-6, "clearance is the whole disc")
	assert_eq(assessment.outward_radial_speed, 0.0, "outward speed is not a survival signal")
	assert_eq(assessment.edge_position_advantage, 0.0, "and there is no cliff to exploit")


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


## ──────────────── THE CPU PAYS FOR ITS DASHES (STAMINA-004) ─────────────────

const STAMINA_DUEL_SEED := 1
const STAMINA_DUEL_TICKS := 1800


## The CPU obeys the same stamina law as a human (CPU-001): it reads its own
## bar and never starts typing a dash it could not pay for, so its footwork is
## never spent on a gesture the duel would refuse. Seed 1 dashes when it can
## pay and begins none when pinned under the cost. Rules 56, with authority
## stuck on the floor, had seed 1 begin none and used seed 2; rules 57
## recovers, and seed 1 is the witness again. No profile weight changed.
func test_the_cpu_never_types_a_dash_it_cannot_afford() -> void:
	## ARRANGE: a Hard v Hard duel left alone dashes.
	var free := _stamina_duel(-1.0)
	assert_true(free.x > 0, "fixture: left alone, the CPU dashes (%d gestures begun)" % free.x)
	## PERTURB: the first CPU's stamina pinned under one dash's cost every tick.
	var cost := DuelFixture.rules().combat.stamina_dash_cost
	## ACT
	var pinned := _stamina_duel(cost * 0.5)
	## ASSERT
	assert_eq(pinned.x, 0, "pinned under the cost, it begins no dash gesture")
	assert_eq(pinned.y, 0, "and the duel starts none for it")


## One Hard v Hard duel for `STAMINA_DUEL_TICKS`: [dash gestures the first CPU
## began, dashes started for it]. A `pin` ≥ 0 holds its stamina there.
func _stamina_duel(pin: float) -> Vector2i:
	var duel := CpuLadder.session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.HARD, STAMINA_DUEL_SEED)
	var started := 0
	while not duel.is_finished() and duel.state.tick < STAMINA_DUEL_TICKS:
		if pin >= 0.0:
			duel.state.fighter(0).stamina = pin
		for event in duel.step():
			if event.type == DuelEventTypes.BURST_STARTED and event.actor == 0:
				started += 1
	return Vector2i((duel.controllers[0] as CpuController).bursts_begun, started)


## No difficulty changes a stamina number: every profile plays under the one
## rule set's costs and floors.
func test_no_difficulty_carries_a_stamina_advantage() -> void:
	## ARRANGE + ACT
	var easy := CpuLadder.session(MatchConfig.Difficulty.EASY, MatchConfig.Difficulty.HARD, 1)
	## ASSERT: both seats compile the same tuning, whatever the difficulty.
	var combat := easy.config.rules.combat
	for field: String in ["stamina_force_floor", "stamina_dash_cost", "stamina_move_cost", "stamina_turn_cost", "stamina_swing_cost", "stamina_recovery_rate"]:
		assert_eq(combat.get(field), StandardDuelRules.combat_tuning().get(field), "%s is the rules' own" % field)
	for profile: CpuProfile in [CpuProfile.easy(), CpuProfile.medium(), CpuProfile.hard()]:
		for property in profile.get_property_list():
			assert_false(String(property.name).contains("stamina"), "no profile carries a stamina number (%s)" % property.name)

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


## ─────────────────────────── CAPITALIZE (CPU-008) ───────────────────────────
##
## Decision-function laws: given a perceived state, which commands the CPU
## chooses. Each is read from a held scene — the bodies stand as placed and
## only the clock moves, so the CPU's delayed perception fills with one
## picture and every decision reads the same physics. Gameplay itself is
## proven elsewhere (ATTACK's line and human-capitalize witnesses, the
## interaction audit); these say what the policy does with a state.


## The CPU (slot 0) at the origin facing +x, `offset` off the opponent's line;
## the opponent (slot 1) `distance` ahead facing back, its sword at θ
## `opponent_angle` in `phase` (RECOVERY: still owing its recovery).
## `reflect` mirrors the scene in y. Returns [controller, last command, state,
## whether it ever capitalized, the clear side it last chose].
func _held_capitalize_scene(distance: float, offset: float, opponent_angle: float, phase: CombatPhase.Id, reflect: float = 1.0, ticks: int = 12) -> Array:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules, 3)
	state.phase = MatchPhase.Id.ROUND_ACTIVE
	var me := state.fighter(0)
	var them := state.fighter(1)
	DuelFixture.place(me, 0.0, reflect * offset, 0.0)
	me.weapon.reset(-reflect * rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(them, distance, 0.0, PI)
	them.weapon.reset(-reflect * rules.combatant(1).weapon.guard_angle)
	them.weapon.angle = reflect * opponent_angle
	them.weapon.phase = phase
	if phase == CombatPhase.Id.RECOVERY:
		them.weapon.recovery_ticks = 40
		them.weapon.recovery_left = 40
	var cpu := CpuController.create(rules, CpuProfile.hard(), 3, 0)
	var command := PlayerCommand.idle(state.tick)
	var capitalized := false
	var side := 0.0
	for _i in ticks:
		command = cpu.command_for(state, 0)
		if cpu._capitalizing:
			capitalized = true
			side = cpu._clear_side
		state.tick += 1
	return [cpu, command, state, capitalized, side]


## The command's step as a world vector, and the line to the opponent.
func _step_and_line(held: Array) -> Array[Vector2]:
	var command: PlayerCommand = held[1]
	var state: MatchState = held[2]
	var me := state.fighter(0)
	var them := state.fighter(1)
	var line := Vector2(them.x - me.x, them.y - me.y).normalized()
	var step := DuelGeometry.to_world(command.axis_x(), command.axis_y(), line.x, line.y)
	var out: Array[Vector2] = [Vector2(step[0], step[1]), line]
	return out


## An opponent who owes its recovery, its sword on the far side of its line,
## the direct line clear: the CPU capitalizes and closes straight in — the
## side it stands on is only a route constraint, and here nothing obstructs.
func test_an_open_line_is_taken_straight_in() -> void:
	## ARRANGE + ACT
	var held := _held_capitalize_scene(1.9, -0.35, deg_to_rad(-45.0), CombatPhase.Id.RECOVERY)
	## ASSERT
	assert_true(held[3], "an open opponent with a clear direct line is capitalized on")
	assert_eq(held[4], 0.0, "by the direct line")
	var vectors := _step_and_line(held)
	assert_true(vectors[0].dot(vectors[1]) > 0.99, "and the step goes straight at the opponent (%.3f)" % vectors[0].dot(vectors[1]))


## The opponent's sword lies across the direct line. Rules 50 found a beside
## route that reached a hand. Under the torso circle this scene's beside route
## also meets steel, so it is not an opening and the CPU does not capitalize.
## That is what this test proves. A route that is steel on the direct line and
## torso on the beside route is still the intended capitalize behavior, and it
## has no witness here (CPU-ROUTE-001, OPEN). A clear torso line is still taken
## straight (`test_an_open_line_is_taken_straight_in`). The beside offset was
## not retuned.
func test_steel_on_the_direct_line_and_the_beside_route_is_declined() -> void:
	var rules := DuelFixture.rules()
	var state := DuelFixture.state(rules, 3)
	state.phase = MatchPhase.Id.ROUND_ACTIVE
	var me := state.fighter(0)
	var them := state.fighter(1)
	DuelFixture.place(me, 0.0, 0.5, 0.0)
	me.weapon.reset(-rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(them, 2.2, 0.0, PI)
	them.weapon.reset(-rules.combatant(1).weapon.guard_angle)
	them.weapon.angle = deg_to_rad(-105.0)
	them.weapon.phase = CombatPhase.Id.RECOVERY
	them.weapon.recovery_ticks = 40
	them.weapon.recovery_left = 40
	var seen := CpuObservation.observe(state, 0, rules)
	var direct := Vector2(them.x - me.x, them.y - me.y).normalized()
	var straight := seen.route_reading(rules, direct.x, direct.y, ThreatEstimate.new())
	var cpu := CpuController.create(rules, CpuProfile.hard(), 3, 0)
	cpu._sight_x = them.x
	cpu._sight_y = them.y
	cpu._sight_facing = them.facing
	var beside := cpu._route_beside(me, cpu._side_away_from_blade(seen))
	var around := seen.route_reading(rules, beside.x, beside.y, ThreatEstimate.new())
	assert_eq(straight.first_contact, ThreatEstimate.STEEL, "the direct line meets steel before the torso")
	assert_eq(around.first_contact, ThreatEstimate.STEEL, "and the beside route does too: it is not a torso opening")
	var held := _held_capitalize_scene(2.2, 0.5, deg_to_rad(-105.0), CombatPhase.Id.RECOVERY)
	assert_false(held[3], "so the CPU does not capitalize on it")


## THREAT-001 / FIRST-CONTACT-001 at its lowest owner: the predictor sweeps
## steel between its ticks as the duel's substeps do, so a blade that crosses
## the other inside one tick cannot be skipped. One predictor tick in which
## slot 0's heading swings from +0.4 to −0.4 rad across slot 1's sword, slot 1
## standing 1.4 m ahead: clear of steel at both of the tick's ends, crossing it
## in between — the sweep finds it inside the tick; the same swing with slot 1
## out of reach finds nothing. (The live witnesses — agreement-audit samples
## where the sweep decided the reading — each went with a later change to live
## play; on the final rules 52 the audit has none.)
func test_a_fast_blade_cannot_skip_the_steel_inside_a_tick() -> void:
	## ARRANGE
	var rules := StandardDuelRules.create()
	var spec := rules.combatant(0)
	var before := PackedFloat64Array([0.0, 0.0, 0.4, 0.0, 1.4, 0.0, PI, 0.0])
	var now := PackedFloat64Array([0.0, 0.0, -0.4, 0.0, 1.4, 0.0, PI, 0.0])
	var mid := PackedFloat64Array([0.0, 0.0, 0.2, 0.0, 1.4, 0.0, PI, 0.0])
	assert_true(_steel_clearance_at(before, spec) > 0.0 and _steel_clearance_at(now, spec) > 0.0, "fixture: clear of steel at both ends of the tick (%.4f, %.4f m)" % [_steel_clearance_at(before, spec), _steel_clearance_at(now, spec)])
	assert_true(_steel_clearance_at(mid, spec) <= 0.0, "fixture: crossing it a quarter of the way through")
	## PERTURB: the same swing, slot 1 stood out of reach.
	var far_before := before.duplicate()
	var far_now := now.duplicate()
	far_before[4] = 4.0
	far_now[4] = 4.0
	## ACT
	var found := InitiativeModel._steel_within(before, now, spec, spec, BladePose.new(), BladePose.new(), SwordContactGeometry.new())
	var missed := InitiativeModel._steel_within(far_before, far_now, spec, spec, BladePose.new(), BladePose.new(), SwordContactGeometry.new())
	## ASSERT
	assert_true(found > 0.0 and found < 1.0, "the sweep finds the crossing inside the tick (at %.4f of it)" % found)
	assert_eq(missed, 2.0, "and nothing where no steel is crossed")


## The steel clearance between two swords posed at `at` ([x, y, φ, θ, target
## x, target y, target φ, target θ]), both `spec`.
static func _steel_clearance_at(at: PackedFloat64Array, spec: CombatantPhysicsSpec) -> float:
	var pose := WeaponKinematics.pose_at(at[0], at[1], at[2], at[3], spec, BladePose.new())
	var their := WeaponKinematics.pose_at(at[4], at[5], at[6], at[7], spec, BladePose.new())
	return SwordContactGeometry.new().measure(at[0], at[1], pose.origin_x, pose.origin_y, pose.ux, pose.uy, their.origin_x, their.origin_y, their.ux, their.uy, spec.weapon, spec.weapon)


## The opponent's steel blocks the direct line and the detour alike: no route
## is clear, so the CPU does not throw itself into it.
func test_a_route_only_into_steel_is_declined() -> void:
	var held := _held_capitalize_scene(1.9, 0.35, deg_to_rad(90.0), CombatPhase.Id.RECOVERY)
	assert_false(held[3], "no clear route, no capitalize")


## The swords already bound: the cheap predictor carries no bind constraint,
## so its route reading from a bind is no answer, and the CPU leaves the bind to
## the ordinary utilities and the physics.
func test_a_route_that_starts_in_a_bind_is_not_taken_as_clear() -> void:
	var held := _held_capitalize_scene(1.9, 0.35, deg_to_rad(60.0), CombatPhase.Id.RECOVERY)
	var cpu: CpuController = held[0]
	var state: MatchState = held[2]
	var seen := CpuObservation.observe(state, 0, DuelFixture.rules())
	var line := _step_and_line(held)[1]
	var reading := seen.route_reading(DuelFixture.rules(), line.x, line.y, ThreatEstimate.new())
	assert_true(reading.starts_bound, "fixture: the swords start bound")
	assert_false(held[3], "a bound route is not capitalized on")
	assert_false(cpu._capitalizing, "and no intent is held")


## Six seconds. Long enough to walk in from 1.9 m and release one attack.
## A hit is not the claim.
const TIRED_WINDOW_TICKS := 360


## Stamina under one dash, shared by every difficulty. The bar is the dash
## cost on purpose: guarded probing uses that affordability, and there is no
## second threshold. A guarded rest that owes nothing — not open, no
## intercept, no tempo — starts no intent and no press, release, or attack.
## Recovery is owed. Capitalize may close the distance; the punish is the
## press, the start, and the release inside the window, not the intent.
func test_a_tired_cpu_holds_a_guarded_line_and_still_punishes_an_opening() -> void:
	var cost := DuelFixture.rules().combat.stamina_dash_cost
	var guarded := _tired_play(CombatPhase.Id.NEUTRAL, cost * 0.5)
	var opening := _tired_play(CombatPhase.Id.RECOVERY, cost * 0.5)
	assert_true(bool(guarded["sound"]) and bool(opening["sound"]), "every tick legal")
	assert_true(int(guarded["clear_decisions"]) > 0, "fixture: the guarded rest has decisions that owe nothing")
	assert_eq(int(guarded["intent_while_clear"]), 0, "tired, and nothing owed, it holds no capitalize intent")
	assert_eq(int(guarded["press_while_clear"]), 0, "and it presses no attack")
	assert_eq(int(guarded["release_while_clear"]), 0, "and it releases none")
	assert_eq(int(guarded["started_while_clear"]), 0, "and none starts")
	assert_true(int(guarded["suppressed"]) > 0, "the dash-cost gate is what withheld the probe (%d)" % int(guarded["suppressed"]))
	assert_true(int(opening["open_ticks"]) > 0, "fixture: recovery is an opening")
	assert_true(int(opening["press"]) >= 0, "the punish presses (tick %d)" % int(opening["press"]))
	assert_true(int(opening["started"]) >= int(opening["press"]), "the attack starts on that press (tick %d)" % int(opening["started"]))
	assert_true(int(opening["released"]) >= int(opening["started"]), "and it releases inside %d ticks (tick %d)" % [TIRED_WINDOW_TICKS, int(opening["released"])])


## The same place as the guarded-rest capitalize scene, then the real
## simulation. Stamina is pinned under the dash cost each tick. The opponent
## stands idle. Recovery lasts the window, so the opening is not a one-tick pose.
func _tired_play(phase: CombatPhase.Id, stamina: float) -> Dictionary:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var state := runner.state
	var me := state.fighter(0)
	var them := state.fighter(1)
	DuelFixture.place(me, 0.0, -0.35, 0.0)
	me.weapon.reset(-rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(them, 1.9, 0.0, PI)
	them.weapon.reset(-rules.combatant(1).weapon.guard_angle)
	them.weapon.angle = deg_to_rad(-45.0)
	them.weapon.phase = phase
	if phase == CombatPhase.Id.RECOVERY:
		them.weapon.recovery_ticks = TIRED_WINDOW_TICKS
		them.weapon.recovery_left = TIRED_WINDOW_TICKS
	var cpu := CpuController.create(rules, CpuProfile.hard(), 3, 0)
	var out := {
		"sound": true,
		"clear_decisions": 0,
		"intent_while_clear": 0,
		"press_while_clear": 0,
		"release_while_clear": 0,
		"started_while_clear": 0,
		"suppressed": 0,
		"open_ticks": 0,
		"press": -1,
		"started": -1,
		"released": -1,
	}
	var last_clear := false
	var saw := false
	for _i in TIRED_WINDOW_TICKS:
		me.stamina = stamina
		var before_traces := cpu.traces.size()
		var before_events := runner.events.size()
		var command := cpu.command_for(state, 0)
		if cpu.traces.size() > before_traces:
			var trace: CpuDecisionTrace = cpu.traces.back()
			var owed := trace.owed_open or trace.owed_intercept or trace.tempo_opportunity > 0.0
			last_clear = not owed
			saw = true
			if last_clear:
				out["clear_decisions"] = int(out["clear_decisions"]) + 1
				if trace.capitalizing:
					out["intent_while_clear"] = int(out["intent_while_clear"]) + 1
		if saw and last_clear:
			if command.attack_pressed:
				out["press_while_clear"] = int(out["press_while_clear"]) + 1
			if command.attack_released:
				out["release_while_clear"] = int(out["release_while_clear"]) + 1
		if command.attack_pressed and int(out["press"]) < 0:
			out["press"] = state.tick
		if CpuObservation.observe(state, 0, rules).opponent_open():
			out["open_ticks"] = int(out["open_ticks"]) + 1
		runner.push(command, PlayerCommand.idle(state.tick))
		for index in range(before_events, runner.events.size()):
			var event: DuelEvent = runner.events[index]
			if event.actor != 0:
				continue
			if event.type == DuelEventTypes.ATTACK_STARTED:
				if int(out["started"]) < 0:
					out["started"] = event.tick
				if saw and last_clear:
					out["started_while_clear"] = int(out["started_while_clear"]) + 1
			elif event.type == DuelEventTypes.ATTACK_RELEASED and int(out["released"]) < 0:
				out["released"] = event.tick
		if phase == CombatPhase.Id.RECOVERY and int(out["released"]) >= 0:
			break
	out["suppressed"] = cpu.probes_suppressed
	out["sound"] = runner.is_sound()
	return out


## A guarded opponent at rest owes nothing: neutral is the ordinary utilities'
## business, never a capitalize.
func test_a_guarded_opponent_at_rest_is_not_an_opening() -> void:
	var held := _held_capitalize_scene(1.9, -0.35, deg_to_rad(-45.0), CombatPhase.Id.NEUTRAL)
	assert_false(held[3], "neutral is not capitalized on")


## CPU-008 in live play (integration, not a held scene): one Hard–Medium duel
## on an audit seed, real physics and real delayed perception throughout. The
## intent is chosen, some of its starts are followed within half a second by
## the capitalizer's body hit, some are abandoned without a strike when the
## physics stops supporting them, and none starts while the CPU is already
## striking. (That its commands are legal input is owned by
## `test_the_cpu_never_types_a_dash_it_did_not_decide_on` and `PlayerCommand`.)
func test_the_capitalize_intent_lives_in_real_play() -> void:
	## ARRANGE
	var duel := CpuLadder.session(MatchConfig.Difficulty.HARD, MatchConfig.Difficulty.MEDIUM, 201)
	var starts := 0
	var converted := 0
	var abandoned := 0
	var while_striking := 0
	var was := [false, false]
	var pending := [-1, -1]
	var struck := [false, false]
	## ACT
	while not duel.is_finished() and duel.state.tick < CpuLadder.MAX_TICKS:
		var striking_before := [CombatPhase.is_striking(duel.state.fighter(0).weapon.phase), CombatPhase.is_striking(duel.state.fighter(1).weapon.phase)]
		var events := duel.step()
		for slot in 2:
			var cpu := duel.controllers[slot] as CpuController
			if cpu._capitalizing and not was[slot]:
				starts += 1
				pending[slot] = duel.state.tick
				struck[slot] = false
				if striking_before[slot]:
					while_striking += 1
			if cpu._capitalizing:
				struck[slot] = struck[slot] or CombatPhase.is_striking(duel.state.fighter(slot).weapon.phase)
			if was[slot] and not cpu._capitalizing and not struck[slot]:
				abandoned += 1
			was[slot] = cpu._capitalizing
		for event in events:
			if event.type == DuelEventTypes.BODY_HIT and pending[event.actor] >= 0 and event.tick - pending[event.actor] <= 30:
				converted += 1
				pending[event.actor] = -1
	## ASSERT
	assert_true(starts > 0, "the intent is chosen in real play (%d starts)" % starts)
	assert_true(converted > 0, "some starts are followed by the capitalizer's hit (%d)" % converted)
	assert_true(abandoned > 0, "some are dropped without a strike once the opening closes (%d)" % abandoned)
	assert_eq(while_striking, 0, "none starts while the CPU is already striking")


## Mirrored, the decision, the route and the command mirror exactly — straight
## in and around the blade alike.
func test_capitalizing_mirrors_exactly() -> void:
	for scene: Array in [[1.9, -0.35, deg_to_rad(-45.0)], [1.7, 0.4, deg_to_rad(-60.0)]]:
		var plain := _held_capitalize_scene(scene[0], scene[1], scene[2], CombatPhase.Id.RECOVERY)
		var mirrored := _held_capitalize_scene(scene[0], scene[1], scene[2], CombatPhase.Id.RECOVERY, -1.0)
		var a: PlayerCommand = plain[1]
		var b: PlayerCommand = mirrored[1]
		assert_true(plain[3] and mirrored[3], "fixture: both capitalize (%.1f m)" % scene[0])
		assert_eq(mirrored[4], -float(plain[4]), "from mirrored routes")
		assert_eq(b.move_x, -a.move_x, "the lateral step mirrors")
		assert_eq(b.move_y, a.move_y, "the forward step is the same")
		assert_eq(b.attack_pressed, a.attack_pressed, "and so is the attack")


# ── CPU-009: the range preference ───────────────────────────────────────────


## A held range scene: a CPU in slot 0 playing `profile` and an opponent that
## stands idle in Long Guard, `start` metres apart on the duel's own line,
## after the intro: [runner, cpu].
func _range_scene(profile: CpuProfile, start: float, seed_value: int) -> Array:
	var rules := StandardDuelRules.create()
	var runner := SimRunner.create(rules, seed_value)
	runner.skip_intro()
	var a := runner.state.fighter(0)
	var b := runner.state.fighter(1)
	var cx := (a.x + b.x) * 0.5
	var cy := (a.y + b.y) * 0.5
	var line := Vector2(b.x - a.x, b.y - a.y).normalized()
	DuelFixture.place(a, cx - line.x * start * 0.5, cy - line.y * start * 0.5, atan2(line.y, line.x))
	DuelFixture.place(b, cx + line.x * start * 0.5, cy + line.y * start * 0.5, atan2(-line.y, -line.x))
	return [runner, CpuController.create(rules, profile, seed_value, 0)]


## Run a range scene until the CPU releases its first attack (at most
## `ticks`): the closest the two came before it, the tick of the CPU's first
## burst (−1 none), the first tick it stood beyond `line` (−1 never), the
## release tick (−1 none), and whether every tick was legal.
func _until_release(scene: Array, ticks: int, line: float) -> Dictionary:
	var runner: SimRunner = scene[0]
	var cpu: CpuController = scene[1]
	var out := {"closest": INF, "burst": -1, "beyond": -1, "released": -1}
	for t in ticks:
		var seen := runner.events.size()
		runner.push(cpu.command_for(runner.state, 0), PlayerCommand.idle(runner.state.tick))
		var d := DuelGeometry.distance(runner.state.fighter(0), runner.state.fighter(1))
		if int(out["beyond"]) < 0 and d >= line:
			out["beyond"] = t
		for i in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[i]
			if event.actor != 0:
				continue
			if event.type == DuelEventTypes.BURST_STARTED and int(out["burst"]) < 0:
				out["burst"] = t
			elif event.type == DuelEventTypes.ATTACK_RELEASED:
				out["released"] = t
		if int(out["released"]) >= 0:
			break
		out["closest"] = minf(float(out["closest"]), d)
	out["sound"] = runner.is_sound()
	return out


## CPU-009: a forward dash spends its whole travel at once — the burst and its
## glide to rest — so the CPU takes one only when that travel still stops
## outside the range it is closing to. Against an opponent standing in Long
## Guard, with the dash made certain (`burst_weight` 1): from far enough that a
## dash stops outside its ready range it still dashes, and comes no closer
## than its smothered line before it strikes; from where one dash would carry
## it inside its ready range it walks in instead, just as close. Seeds 1–3.
func test_a_dash_in_never_carries_the_cpu_inside_its_own_range() -> void:
	var dasher := CpuProfile.hard()
	dasher.burst_weight = 1.0
	for seed_value: int in [1, 2, 3]:
		## ARRANGE: the distances from this CPU's own range and dash.
		var sizing: CpuController = _range_scene(dasher, 3.0, seed_value)[1]
		var ready := sizing.preferred_range(true)
		var dash := sizing.dash_travel()
		var smothered := sizing.smothered_line()
		var far := ready + dash + 1.0
		var near := ready + dash * 0.5
		assert_true(near - dash < smothered and near > ready, "fixture: from %.2f m one dash (%.2f m) would carry it inside its smothered line (%.2f m)" % [near, dash, smothered])
		## ACT
		var from_far := _until_release(_range_scene(dasher, far, seed_value), 300, smothered)
		var from_near := _until_release(_range_scene(dasher, near, seed_value), 300, smothered)
		## ASSERT
		var label := "seed %d" % seed_value
		assert_true(int(from_far["released"]) >= 0 and int(from_near["released"]) >= 0, "%s fixture: both approaches end in an attack" % label)
		assert_true(int(from_far["burst"]) >= 0, "%s: from %.2f m the CPU still dashes in" % [label, far])
		assert_true(float(from_far["closest"]) >= smothered, "%s: and stops outside its smothered line (closest %.3f m)" % [label, float(from_far["closest"])])
		assert_eq(int(from_near["burst"]), -1, "%s: from %.2f m it does not dash" % [label, near])
		assert_true(float(from_near["closest"]) >= smothered, "%s: and walks in no closer than its smothered line (closest %.3f m)" % [label, float(from_near["closest"])])
		assert_true(bool(from_far["sound"]) and bool(from_near["sound"]), "%s: every tick legal" % label)


## CPU-009: a CPU free to act that finds itself inside its smothered line steps
## back out of it before it attacks. Hard against an opponent standing in Long
## Guard, started at 0.7 and 0.9 m with its sword at rest and able to strike —
## a forced state such as a stagger is never asked to move. Seeds 1–3.
func test_a_smothered_cpu_that_can_act_steps_back_out_before_it_attacks() -> void:
	var hard := CpuProfile.hard()
	for seed_value: int in [1, 2, 3]:
		for start: float in [0.7, 0.9]:
			## ARRANGE
			var scene := _range_scene(hard, start, seed_value)
			var runner: SimRunner = scene[0]
			var cpu: CpuController = scene[1]
			var me := runner.state.fighter(0)
			var label := "seed %d from %.1f m" % [seed_value, start]
			assert_true(start < cpu.smothered_line(), "%s fixture: inside the smothered line (%.2f m)" % [label, cpu.smothered_line()])
			assert_true(me.weapon.phase == CombatPhase.Id.NEUTRAL and WeaponSystem.can_start_attack(me, runner.rules.spec_of(me).weapon), "%s fixture: free to act" % label)
			## ACT
			var outcome := _until_release(scene, 300, cpu.smothered_line())
			## ASSERT
			assert_true(int(outcome["beyond"]) >= 0, "%s: it steps back out of its smothered line" % label)
			assert_true(int(outcome["released"]) < 0 or int(outcome["beyond"]) <= int(outcome["released"]), "%s: before it attacks (out at %d, release at %d)" % [label, int(outcome["beyond"]), int(outcome["released"])])
			assert_true(bool(outcome["sound"]), "%s: every tick legal" % label)


## THREAT-001 / FIRST-CONTACT-001 as the CPU sees it: in a constructed scene
## the predictor's own reading needs its in-tick steel sweep — slot 0 at rest
## and able to strike; slot 1 1.8 m ahead, 0.2 m to the side, its own cut in
## flight (from −0.8 rad at 8 rad/s), so the two blades cross between the
## predictor's ticks. The route estimate reads steel first, and on the tick the
## duel meets it: the duel, continued as the estimate assumes (slot 0's route
## tap, slot 1 carrying on), meets slot 1's blade before any flesh. (A copy of
## the predictor without the sweep reads the torso here; the same scene at
## 2.4 m reads the same, so the distance is no knife edge.)
func test_the_route_estimate_sees_a_blade_crossing_between_its_ticks() -> void:
	## ARRANGE
	var rules := StandardDuelRules.create()
	var runner := SimRunner.create(rules, 5)
	runner.skip_intro()
	var weapon := rules.combatant(0).weapon
	ContactFixture.arm(runner.state.fighter(0), 0.0, 0.0, 0.0, -weapon.guard_angle, 0.0, CombatPhase.Id.NEUTRAL, 0.0, weapon)
	ContactFixture.arm(runner.state.fighter(1), 1.8, 0.2, PI, -0.8, 8.0, CombatPhase.Id.ACTIVE_THREAT, 0.5, weapon)
	var me := runner.state.fighter(0)
	var them := runner.state.fighter(1)
	assert_true(WeaponSystem.can_start_attack(me, weapon), "fixture: slot 0 can strike")
	assert_true(ContactGauge.blades(rules, runner.state).x > 0.0, "fixture: the blades start apart")
	## ACT: the estimate, then the duel under its continuation.
	var predicted := InitiativeModel.estimate(me, rules.spec_of(me), them, rules.spec_of(them), rules.combat, ThreatEstimate.new(), ThreatContinuation.route(1.0, 0.0))
	var clash_tick := -1
	var flesh := false
	var launched := false
	for t in 30:
		var a := runner.state.fighter(0)
		var step := CutGeometry.step_intent(a, runner.state.fighter(1), Vector2(1.0, 0.0))
		var press := not launched and WeaponSystem.can_start_attack(a, rules.spec_of(a).weapon)
		var seen := runner.events.size()
		runner.push(PlayerCommand.create(runner.state.tick, step.x, step.y, press, press), PlayerCommand.idle(runner.state.tick))
		launched = launched or press
		for i in range(seen, runner.events.size()):
			var event: DuelEvent = runner.events[i]
			if clash_tick < 0 and event.type == DuelEventTypes.BLADE_CONTACT:
				clash_tick = t + 1
			elif clash_tick < 0 and event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
				flesh = true
		if clash_tick >= 0:
			break
	## ASSERT
	assert_true(clash_tick >= 0 and not flesh, "fixture: the duel's tap meets steel before any flesh (tick %d)" % clash_tick)
	assert_eq(predicted.first_contact, ThreatEstimate.STEEL, "the estimate sees the steel, not the torso behind it")
	assert_near(predicted.steel_time, float(clash_tick) * SimulationTimebase.TICK_SECONDS, SimulationTimebase.TICK_SECONDS * 0.5, "on the tick the duel meets it")
	assert_true(runner.is_sound(), "every tick legal")
