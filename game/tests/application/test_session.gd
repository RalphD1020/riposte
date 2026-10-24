extends TestCase

## SESSION: configs compose the right controllers; sessions record, verify,
## replay, and summarize (PLAN Phases 11, 13).
##
## See also: /docs/concepts/simulation.md


func _init() -> void:
	suite_name = "SESSION"


func _finished_cpu_session(seed_value: int) -> MatchSession:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, seed_value)
	var controllers: Array[FighterController] = [
		CpuController.create(config.rules, CpuProfile.medium(), seed_value, 0),
		CpuController.create(config.rules, CpuProfile.hard(), seed_value, 1),
	]
	var session := MatchSession.create(config, controllers)
	while not session.is_finished() and session.state.tick < 40000:
		session.step()
	return session


func test_the_product_arena_is_closed_and_the_open_fixture_stays_open() -> void:
	var open := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, 5)
	assert_false(open.rules.is_closed_edge(), "MatchConfig.quick_play is the open-edge fixture")
	assert_eq(open.rules.version, 58, "and it stays version 58")
	var stage := StageCatalog.arena()
	assert_eq(stage.problem(), "", "The Arena can start")
	assert_true(stage.has_crowd, "The Arena has a crowd")
	assert_true(stage.has_crowd_bed, "and it keeps the ambient bed")
	assert_eq(stage.basin, StageDefinition.Basin.NONE, "and no basin")
	var product := MatchConfig.for_stage(stage, MatchConfig.Difficulty.HARD, 5)
	assert_true(product.rules.is_closed_edge(), "the product stage closes the edge")
	assert_eq(product.rules.version, 60, "on version 60")
	assert_eq(product.palette_slot, PackedInt32Array([0, 1]), "Main versus Alternate")
	assert_true(product.crowd_bed, "the match copies the bed flag")
	var quiet := StageDefinition.new()
	quiet.stage_id = &"stage.quiet"
	quiet.kit_id = ContentIds.ARENA_STANDARD
	quiet.display_name = "Quiet"
	quiet.has_crowd = true
	quiet.has_crowd_bed = false
	quiet.closed_edge = true
	var quiet_match := MatchConfig.for_stage(quiet, MatchConfig.Difficulty.MEDIUM, 5)
	assert_false(quiet_match.crowd_bed, "a crowd stage can omit the bed")
	assert_false(quiet_match.rematch(6).crowd_bed, "a rematch keeps that choice")
	var water := StageDefinition.new()
	water.stage_id = &"stage.water"
	water.kit_id = ContentIds.ARENA_STANDARD
	water.display_name = "Water"
	water.basin = StageDefinition.Basin.WATER
	water.basin_height = NAN
	assert_eq(water.problem(), "a water stage needs a surface height", "water without a height does not start")
	var rules := StandardDuelRules.pit()
	var push := rules.combatant(0).fighter.push_radius
	var half := rules.combatant(0).fighter.lying_half_length
	assert_true(rules.spawn_offset + half < rules.platform_radius - push, "both spawns leave room for a lying body")


func test_the_end_is_an_open_deck_and_a_rematch_stays_there() -> void:
	var open := StandardDuelRules.create()
	assert_eq(open.arena_id, ContentIds.ARENA_STANDARD, "version 58 still names the Arena")
	var stage := StageCatalog.the_end()
	assert_eq(stage.problem(), "", "The End can start")
	assert_false(stage.closed_edge, "open edge")
	assert_false(stage.has_crowd, "no crowd")
	assert_false(stage.has_crowd_bed, "no bed")
	assert_eq(stage.basin, StageDefinition.Basin.NONE, "no basin")
	var config := MatchConfig.for_stage(stage, MatchConfig.Difficulty.MEDIUM, 3)
	assert_false(config.rules.is_closed_edge(), "the match is the open disc")
	assert_eq(config.rules.version, 58, "version 58")
	assert_eq(config.rules.arena_id, ContentIds.ARENA_END, "its kit is the deck")
	assert_false(config.crowd_bed, "the match copies the quiet flag")
	assert_eq(config.basin, StageDefinition.Basin.NONE, "and copies the empty basin")
	var again := config.rematch(4)
	assert_eq(again.rules.arena_id, ContentIds.ARENA_END, "a rematch stays on the deck")
	assert_false(again.rules.is_closed_edge(), "and stays open")
	assert_eq(again.stage_id, ContentIds.ARENA_END, "the stage id stays")
	var quick := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, 5)
	var quick_again := quick.rematch(6)
	assert_false(quick_again.rules.is_closed_edge(), "an open fixture rematch stays open")
	assert_eq(quick_again.rules.arena_id, ContentIds.ARENA_STANDARD, "and does not become the deck")
	var water := StageDefinition.new()
	water.stage_id = &"stage.water.ready"
	water.kit_id = ContentIds.ARENA_STANDARD
	water.display_name = "Water"
	water.basin = StageDefinition.Basin.WATER
	water.basin_height = -2.5
	assert_eq(water.problem(), "", "a water fixture with a height can start")
	var flooded := MatchConfig.for_stage(water, MatchConfig.Difficulty.MEDIUM, 1)
	assert_eq(flooded.basin, StageDefinition.Basin.WATER, "the match copies the request")
	assert_near(flooded.basin_height, -2.5, 1e-4, "and the surface height")
	assert_true(ResourceLoader.exists(StageCatalog.DECK_SCENE), "the deck file is in the game")
	var listed := false
	for item: StageDefinition in StageCatalog.playable():
		if item.stage_id == ContentIds.ARENA_END:
			listed = true
	assert_true(listed, "Fight Setup lists The End")


## Rematch carries the stage it was started on. It never reads the live edge:
## a match whose rules were swapped to the other edge still rematches as its
## stage, with that stage's rules, kit, crowd bed, and basin.
func test_a_rematch_is_the_same_stage_whatever_the_edge_says() -> void:
	var stages: Array[StageDefinition] = [StageCatalog.arena(), StageCatalog.the_end(), StageCatalog.open_disc()]
	for stage: StageDefinition in stages:
		assert_eq(stage.problem(), "", "%s: fixture: the stage can start" % stage.stage_id)
		var config := MatchConfig.for_stage(stage, MatchConfig.Difficulty.MEDIUM, 7)
		config.palette_slot = PackedInt32Array([1, 0])
		var expected_edge := config.rules.is_closed_edge()
		config.rules = StandardDuelRules.create() if expected_edge else StandardDuelRules.pit()
		assert_ne(config.rules.is_closed_edge(), expected_edge, "%s: fixture: the live rules now say the other edge" % stage.stage_id)
		var again := config.rematch(8)
		assert_true(again.stage == stage, "%s: the rematch is the same stage" % stage.stage_id)
		assert_eq(again.stage_id, stage.stage_id, "%s: and keeps its id" % stage.stage_id)
		assert_eq(again.rules.is_closed_edge(), stage.closed_edge, "%s: with the stage's edge, not the live one" % stage.stage_id)
		assert_eq(again.rules.arena_id, stage.kit_id, "%s: and the stage's kit" % stage.stage_id)
		assert_eq(again.crowd_bed, stage.has_crowd_bed, "%s: and its crowd bed" % stage.stage_id)
		assert_eq(again.basin, stage.basin, "%s: and its basin" % stage.stage_id)
		assert_eq(again.palette_slot, PackedInt32Array([1, 0]), "%s: and the launched palettes" % stage.stage_id)
		var twice := again.rematch(9)
		assert_true(twice.stage == stage and twice.rules.arena_id == stage.kit_id, "%s: a second rematch is still that stage" % stage.stage_id)
	assert_eq(MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, 1).stage_id, ContentIds.STAGE_OPEN_DISC, "quick_play is the open-disc fixture by name")
	var listed: Array[StringName] = []
	for item: StageDefinition in StageCatalog.playable():
		listed.append(item.stage_id)
	assert_false(listed.has(ContentIds.STAGE_OPEN_DISC), "the fixture is never offered in Fight Setup")
	assert_true(StageCatalog.of(ContentIds.STAGE_OPEN_DISC) == null, "and Fight Setup cannot start it by id")
	var nameless := StageCatalog.arena()
	nameless.kit_id = &""
	assert_eq(nameless.problem(), "the stage has no identity", "a stage without a kit does not start")
	assert_eq(MatchConfig.training(3).stage_id, &"", "training has no stage")


func test_quick_play_is_human_versus_cpu() -> void:
	var human := HumanController.new()
	var session := MatchComposer.compose(MatchConfig.quick_play(MatchConfig.Difficulty.HARD, 5), human)
	assert_true(session.controllers[0] == human, "slot 0 is the local human")
	var cpu := session.controllers[1] as CpuController
	assert_true(cpu != null, "slot 1 is the CPU")
	assert_eq(cpu.profile.difficulty, MatchConfig.Difficulty.HARD, "chosen difficulty")
	assert_eq(session.config.rules.id, ContentIds.RULES_STANDARD_DUEL, "standard rules")


func test_training_is_a_non_lethal_dummy() -> void:
	var session := MatchComposer.compose(MatchConfig.training(5), HumanController.new())
	assert_true(session.controllers[1] is TrainingDummyController, "training partner")
	assert_eq(session.config.rules.id, ContentIds.RULES_TRAINING, "training rules")
	assert_eq(session.config.rules.combat.damage_for(1.0), 0.0, "contact is physical but non-lethal")


func test_rematch_keeps_the_mode_with_a_fresh_seed() -> void:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.EASY, 5)
	var again := config.rematch(6)
	assert_eq(again.cpu_difficulty, MatchConfig.Difficulty.EASY, "same difficulty")
	assert_eq(again.seed_value, 6, "new seed")
	assert_true(again.rules != config.rules, "fresh rules instance")
	assert_eq(MatchConfig.training(1).rematch(2).mode, MatchConfig.Mode.TRAINING, "training rematches as training")


func test_finished_sessions_record_verifiable_replays() -> void:
	var session := _finished_cpu_session(8)
	assert_true(session.is_finished(), "precondition: match ended")
	assert_ne(session.record.final_hash, "", "final hash recorded")
	assert_eq(ReplayVerifier.verify(session.record, session.config.rules), ReplayVerifier.VERIFIED, "replay verifies")
	assert_eq(session.step().size(), 0, "a finished session is inert")


func test_replay_controllers_reproduce_the_session() -> void:
	var original := _finished_cpu_session(4)
	var controllers: Array[FighterController] = [
		ReplayController.create(original.record, 0),
		ReplayController.create(original.record, 1),
	]
	var replayed := MatchSession.create(original.config.rematch(original.config.seed_value), controllers)
	while not replayed.is_finished() and replayed.state.tick < 40000:
		replayed.step()
	assert_eq(replayed.record.final_hash, original.record.final_hash, "replay controllers reproduce the duel")


func test_summary_reflects_the_match() -> void:
	var session := _finished_cpu_session(2)
	var summary := session.summary(0)
	var expected: StringName
	if session.state.match_winner == 0:
		expected = MatchSummary.VICTORY
	elif session.state.match_winner == 1:
		expected = MatchSummary.DEFEAT
	else:
		expected = MatchSummary.DRAW
	assert_eq(summary.outcome, expected, "outcome from the match winner")
	var hits := 0
	for event in session.events:
		if event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
			hits += 1
	assert_eq(summary.hits_landed, hits, "hits counted from the log")
	assert_eq(summary.score_self + summary.score_opponent, session.state.scores[0] + session.state.scores[1], "score copied")
	assert_between(summary.average_charge, 0.0, 1.0, "average charge is a charge")


func test_invalid_sessions_fail_closed() -> void:
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, 1)
	var one: Array[FighterController] = [FighterController.new()]
	assert_true(MatchSession.create(config, one) == null, "two controllers required")
	var broken := MatchConfig.quick_play(MatchConfig.Difficulty.MEDIUM, 1)
	broken.rules = DuelRules.new()
	var two: Array[FighterController] = [FighterController.new(), FighterController.new()]
	assert_true(MatchSession.create(broken, two) == null, "invalid rules never start")


func test_monitors_read_the_live_session_and_unregister_cleanly() -> void:
	var monitors := SimulationMonitors.new()
	monitors.install()
	assert_true(Performance.has_custom_monitor(SimulationMonitors.SIM_STEP_US), "the step-cost monitor is registered")
	assert_true(Performance.has_custom_monitor(SimulationMonitors.CCD_CAP_HITS), "and the CCD cap monitor")
	assert_eq(monitors.sim_step_us(), 0, "with no session every monitor reads 0")
	var session := _finished_cpu_session(7)
	assert_true(session.is_finished(), "fixture: a CPU match played to the end")
	session.simulation.diagnostics.ccd_cap_hits = 3
	session.simulation.diagnostics.contact_cap_hits = 2
	session.simulation.diagnostics.rehold_budget_exhausted = 1
	session.simulation.diagnostics.position_guard_hits = 5
	session.simulation.diagnostics.meaningful_contacts_dropped = 4
	session.simulation.diagnostics.pivot_cap_hits = 6
	session.simulation.diagnostics.guard_hard_stop_hits = 7
	monitors.session = session
	assert_eq(monitors.ccd_cap_hits(), 3, "the monitor reads the session's CCD cap counter")
	assert_eq(monitors.contact_cap_hits(), 2, "and its contact cap counter")
	## Perturb-by-contrast: distinct values per counter, so a monitor wired to
	## the wrong counter (or to a sum) reads a wrong number.
	assert_eq(monitors.rehold_budget_exhausted(), 1, "the re-hold budget has its own monitor")
	assert_eq(monitors.position_guard_hits(), 5, "and so does the position-stage turn guard, never summed with it")
	assert_eq(monitors.meaningful_contacts_dropped(), 4, "and the count of real constraints a feature pair could not hold")
	assert_eq(monitors.pivot_cap_hits(), 6, "and the exact block's pivot cap")
	assert_eq(monitors.guard_hard_stop_hits(), 7, "and the guard limit's hard-stop fallback")
	for id: StringName in SimulationMonitors.ALL:
		assert_true(Performance.has_custom_monitor(id), "%s is registered" % id)
	assert_true(monitors.max_manifold_points() >= 1 and monitors.max_manifold_points() <= SwordContactSet.CAPACITY, "a played match touched swords within capacity (%d)" % monitors.max_manifold_points())
	assert_eq(monitors.sim_step_us(), session.last_step_usec, "and the cost of its last step")
	monitors.uninstall()
	for id: StringName in SimulationMonitors.ALL:
		assert_false(Performance.has_custom_monitor(id), "uninstall removes %s" % id)
	assert_true(monitors.session == null, "and releases the session")


func test_training_dummy_answers_only_inside_reach() -> void:
	var rules := StandardDuelRules.training()
	var runner := SimRunner.create(rules, 3)
	runner.skip_intro()
	var dummy := TrainingDummyController.create(rules)
	var far := false
	for _i in TrainingDummyController.ATTACK_INTERVAL_TICKS + 5:
		far = far or dummy.command_for(runner.state, 1).attack_pressed
	assert_false(far, "no attack while the player is out of reach")
	## Step the player into the dummy's reach along the line between them,
	## whichever way the seeded sides put it (SIDE-001).
	var player := runner.state.fighter(0)
	var dummy_body := runner.state.fighter(1)
	player.x = dummy_body.x + SimMath.cosine(dummy_body.facing) * 1.2
	player.y = dummy_body.y + SimMath.sine(dummy_body.facing) * 1.2
	var answered := false
	for _i in TrainingDummyController.ATTACK_INTERVAL_TICKS + 5:
		answered = answered or dummy.command_for(runner.state, 1).attack_pressed
	assert_true(answered, "a quick cut once the player steps in")
