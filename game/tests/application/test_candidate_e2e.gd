extends TestCase

## CANDIDATE-E2E: the unshipped P3 presentation candidate inside the real game.
## Every case boots the shipped `main.tscn`, dresses one participant with the
## candidate through `RiposteApp.fighter_skin_override` (before anything is
## instantiated), and drives the human only through real input, one tick per
## frame, on the open-edge scenario against a standing opponent. It proves:
## the candidate is the scene that actually runs (fingerprinted), the opponent
## keeps the shipping look, the authoritative duel under the same inputs is
## identical with and without it (skins are never read by the simulation), and
## both hands stay on their grips through full charged cuts from each side, read
## from the final post-modifier skeleton.
##
## The candidate is a git-ignored local asset: this suite runs only when asked
## (`pnpm test:candidate`, tier `candidate`) and fails closed — a missing or
## changed candidate is a failure, never a fallback to the shipping fighter.
## Not covered here: W-THRUST (not implemented), the production Arena (v62).
##
## See also: /docs/reference/testing.md

const CANDIDATE := "res://assets/candidates/prod_d6_p3v7_hg_wrapper.tscn"
const CANDIDATE_BODY := "res://assets/candidates/prod_d6_p3v7.glb"
## The candidate this suite was written against; a new candidate is a
## deliberate update of these, never an automatic one.
const CANDIDATE_SHA256 := "1ac545880dabb7f01046b5d252e29112f916903ccb06a775f29ca6e923b0e166"
const CANDIDATE_BODY_SHA256 := "6df44b76a89e4d09df68fdaee3c385098cfa3c75ad35e5dd36a99386abfd24c8"
const SCENARIO_SEED := 11
## PRES-RIG's grip tolerance: a palm this far from its grip is off the handle.
const GRIP_TOLERANCE := 0.035
## Frames allowed for one charge, release and recovery back to the guard.
const CUT_FRAMES := 360


func _init() -> void:
	suite_name = "CANDIDATE-E2E"


## The candidate as a fighter skin, or null after recording why (fail closed).
func _candidate_skin() -> FighterSkinKit:
	for pair: Array in [[CANDIDATE, CANDIDATE_SHA256], [CANDIDATE_BODY, CANDIDATE_BODY_SHA256]]:
		if not FileAccess.file_exists(pair[0]):
			assert_true(false, "the P3 candidate %s is missing (git-ignored local asset): materialize it, never fall back to shipping" % pair[0])
			return null
		assert_eq(FileAccess.get_sha256(pair[0]), pair[1], "fixture: %s is the fingerprinted candidate" % pair[0])
	var scene := load(CANDIDATE) as PackedScene
	if scene == null:
		assert_true(false, "the P3 candidate %s does not load" % CANDIDATE)
		return null
	var skin := FighterSkinKit.new()
	skin.skin_id = &"test.p3_candidate"
	skin.scene = scene
	return skin


## The open-edge scenario on `seed_value`, slot 0 optionally dressed with `skin`,
## stepped to the first fighting tick. Not the product Quick Play path.
func _scenario(driver: AppDriver, skin: FighterSkinKit) -> MatchScreen:
	driver.app.fighter_skin_override = [skin, null]
	var opponent := ScenarioController.standing()
	driver.app.compose_session = func(config: MatchConfig, human: HumanController, sink: TelemetrySink) -> MatchSession:
		config.seed_value = SCENARIO_SEED
		var controllers: Array[FighterController] = [human, opponent]
		return MatchSession.create(config, controllers, sink)
	driver.app.start_open_edge()
	await await_frames(1)
	var screen := driver.match_screen()
	screen.skip_intro()
	driver.run_until(screen, func() -> bool: return screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	assert_eq(screen.session.state.phase, MatchPhase.Id.ROUND_ACTIVE, "fixture: the round is live")
	return screen


## One full charged cut through real input from wherever the blade rests: hold
## the attack until the earned charge is full (or `CUT_FRAMES`), release, and
## run back to the guard. One engine frame per tick, so the skeleton's
## modifier stack runs and `watch` reads its final output.
func _full_charge(driver: AppDriver, screen: MatchScreen, watch: Dictionary) -> Dictionary:
	var state := screen.session.state
	var weapon := state.fighter(0).weapon
	var start := weapon.angle
	var released := -1
	var charge := 0.0
	var most := 0.0
	var stamina_at_press := state.fighter(0).stamina
	driver.key(KEY_SPACE, true)
	for frame in CUT_FRAMES:
		most = maxf(most, weapon.charge)
		## Full, or all the wind-back left before the stop (CHARGE-BOUNDARY).
		var at_stop := absf(weapon.angle) >= StandardDuelRules.create().combatant(0).weapon.guard_limit - deg_to_rad(0.5)
		if released < 0 and weapon.phase == CombatPhase.Id.CHARGING and (weapon.charge >= 1.0 or at_stop):
			charge = weapon.charge
			driver.key(KEY_SPACE, false)
			released = frame
		watch["phase"] = weapon.phase
		screen.advance_frame(AppDriver.FRAME)
		await await_frames(1)
		if released >= 0 and frame - released > 10 and weapon.phase == CombatPhase.Id.NEUTRAL:
			break
	driver.key(KEY_SPACE, false)
	return {"start": start, "charge": charge, "released": released, "end_phase": weapon.phase, "dir": weapon.swing_dir,
		"most": most, "angle": weapon.angle, "stamina_at_press": stamina_at_press, "stamina": state.fighter(0).stamina}


## Idle until the blade rests at its Ready guard (within 1°) or a bound passes.
func _settle_to_ready(driver: AppDriver, screen: MatchScreen) -> void:
	var weapon := screen.session.state.fighter(0).weapon
	var ready := StandardDuelRules.create().combatant(0).weapon.guard_angle
	for _frame in CUT_FRAMES:
		if weapon.phase == CombatPhase.Id.NEUTRAL and absf(absf(weapon.angle) - ready) < deg_to_rad(1.0):
			break
		driver.hold_move(0.0, 0.0)
		screen.advance_frame(AppDriver.FRAME)
		await await_frames(1)
	assert_near(rad_to_deg(absf(weapon.angle)), rad_to_deg(ready), 1.0, "fixture: the blade rests at Ready before the charge")


## Reads both hands against their grips every time the skeleton's modifiers
## finish (the final post-IK pose), worst per phase. With authored contacts the
## grip target is the hand bone's own frame (PRES-GRIP-001), so the hand's
## origin is compared; the legacy grip targets the palm.
func _grip_watch(proxy: FighterPresentation3D, watch: Dictionary) -> Callable:
	var rig := proxy.rig()
	var skeleton := rig.skeleton()
	return func() -> void:
		if rig.grip_influence() < 0.999:
			return
		for index in 2:
			var bone := skeleton.find_bone("Hand.R" if index == 0 else "Hand.L")
			var hand := skeleton.global_transform * skeleton.get_bone_global_pose(bone)
			var held := hand.origin if rig.has_contacts() else hand.origin + hand.basis.y.normalized() * SwordRig3D.HAND_LENGTH
			var gap := held.distance_to(rig.grip_target(index).global_position)
			var phase_name: String = CombatPhase.Id.keys()[int(watch.get("phase", 0))]
			var worst: Dictionary = watch.get_or_add("worst", {})
			worst[phase_name] = maxf(float(worst.get(phase_name, 0.0)), gap)
			watch["samples"] = int(watch.get("samples", 0)) + 1


func test_the_candidate_dresses_one_participant_of_a_real_match() -> void:
	var skin := _candidate_skin()
	if skin == null:
		return
	## ARRANGE / ACT
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, skin)
	var dressed := screen.presenter.fighter_proxy(0)
	var shipping := screen.presenter.fighter_proxy(1)
	## ASSERT: the scene that runs for slot 0 is the candidate's own instance, the
	## opponent's is not, and the candidate carries its declared presentation.
	assert_eq(dressed.combatant_kit().fighter_skin, skin, "slot 0 wears the candidate skin")
	assert_eq(dressed.rig().scene_file_path, CANDIDATE, "and the instantiated rig is the candidate scene")
	assert_ne(shipping.rig().scene_file_path, CANDIDATE, "slot 1 keeps the shipping fighter (%s)" % shipping.rig().scene_file_path)
	assert_true(dressed.rig().rear_hand_pivot and dressed.rig().has_contacts(), "the candidate's grip settings are live (pivot, authored contacts)")
	assert_true(dressed.rig().contract_problems().is_empty(), "and pass the grip contract (%s)" % dressed.rig().contract_problems())
	driver.shutdown()
	await await_frames(2)


func test_the_same_inputs_give_the_same_duel_with_or_without_the_candidate() -> void:
	var skin := _candidate_skin()
	if skin == null:
		return
	var runs: Array[Dictionary] = []
	for dress: FighterSkinKit in [skin, null]:
		## ARRANGE: the same seed, scenario and real input script.
		var driver := AppDriver.boot(7)
		await await_frames(1)
		var screen := await _scenario(driver, dress)
		## ACT: a full charged cut through the keys.
		var cut := await _full_charge(driver, screen, {})
		var types := PackedStringArray()
		for event in screen.session.events:
			types.append("%d:%s:%d" % [event.tick, event.type, event.actor])
		runs.append({"cut": cut, "tick": screen.session.state.tick, "hash": StateHasher.hash_state(screen.session.state), "events": types})
		driver.shutdown()
		await await_frames(2)
	## ASSERT: the fixture ran a real full charge, and authority is identical.
	assert_true(float(runs[0]["cut"]["charge"]) >= 0.98, "fixture: the cut was a full charge from Ready (%.3f)" % float(runs[0]["cut"]["charge"]))
	assert_eq(runs[0]["tick"], runs[1]["tick"], "the same number of ticks ran")
	assert_eq(runs[0]["hash"], runs[1]["hash"], "the authoritative state is identical with the candidate and with shipping")
	assert_eq(runs[0]["events"], runs[1]["events"], "and so is every authoritative event")


func test_both_hands_hold_the_grip_through_full_charges_from_each_side() -> void:
	var skin := _candidate_skin()
	if skin == null:
		return
	## ARRANGE
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, skin)
	var proxy := screen.presenter.fighter_proxy(0)
	var skeleton := proxy.rig().skeleton()
	for side_name: String in ["right-origin", "left-origin"]:
		var watch := {}
		var capture := _grip_watch(proxy, watch)
		skeleton.skeleton_updated.connect(capture)
		## ACT: a full charge from the Ready guard (the right first; the first cut
		## leaves the blade on the left, so the second winds from there once the
		## guard return has brought it back to Ready — from where the overswing
		## left it, there is not 90° left to wind, CHARGE-BOUNDARY).
		await _settle_to_ready(driver, screen)
		var cut := await _full_charge(driver, screen, watch)
		skeleton.skeleton_updated.disconnect(capture)
		## ASSERT: the side, a real full charge back to the guard, a final pose read
		## every frame, and both palms on their grips in every phase.
		var expected_side := -1.0 if side_name == "right-origin" else 1.0
		assert_eq(signf(float(cut["start"])), expected_side, "fixture: the %s cut winds from that side (%.1f°)" % [side_name, rad_to_deg(float(cut["start"]))])
		var available := clampf((135.0 - absf(rad_to_deg(float(cut["start"])))) / 90.0, 0.0, 1.0)
		assert_true(float(cut["charge"]) >= available - 0.01, "fixture: %s earned all the charge its start allowed (%.3f of %.3f)" % [side_name, float(cut["charge"]), available])
		assert_true(available >= 0.98, "fixture: %s started at Ready, so that is a full charge (available %.3f; blade at %.1f°, stamina %.2f at the press → %.2f)" % [side_name, available, rad_to_deg(float(cut["angle"])), float(cut["stamina_at_press"]), float(cut["stamina"])])
		assert_eq(cut["end_phase"], CombatPhase.Id.NEUTRAL, "fixture: %s came back to the guard" % side_name)
		assert_true(int(watch.get("samples", 0)) > 60, "fixture: the final skeleton was read through the %s cut (%d samples)" % [side_name, int(watch.get("samples", 0))])
		var worst: Dictionary = watch.get("worst", {})
		for phase_name: String in worst:
			assert_true(float(worst[phase_name]) <= GRIP_TOLERANCE, "%s %s: both palms on their grips (worst %.1f mm)" % [side_name, phase_name, float(worst[phase_name]) * 1000.0])
		assert_true(screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE, "fixture: the round is still live for the next cut")
	driver.shutdown()
	await await_frames(2)
