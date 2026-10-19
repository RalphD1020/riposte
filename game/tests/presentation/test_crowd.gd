extends TestCase

## PRES-CROWD: one shot per tick from kill, ring-out, critical, a clean parry,
## set point, or set win. Intensity is a separate decaying meter. Contacts
## and ROUND_ENDED do not shoot.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-CROWD"


func _event(type: StringName, payload: Dictionary = {}) -> DuelEvent:
	return DuelEvent.create(type, 0, 1, DuelEvent.NONE, payload)


func _live() -> PackedInt32Array:
	return PackedInt32Array([0, 0])


func test_contacts_do_not_move_intensity_or_select_a_cue() -> void:
	var crowd := CrowdDirector.new()
	assert_eq(crowd.observe([_event(DuelEventTypes.BLADE_CONTACT)], _live(), 3, MatchPhase.NO_WINNER), &"", "steel does not shoot")
	assert_eq(crowd.excitement, 0.0, "and does not raise intensity")
	crowd.observe([_event(DuelEventTypes.CRITICAL_HIT)], _live(), 3, MatchPhase.NO_WINNER)
	var after_critical := crowd.excitement
	assert_true(after_critical > 0.2, "fixture: a critical raised the meter")
	assert_eq(crowd.observe([_event(DuelEventTypes.BLADE_CONTACT), _event(DuelEventTypes.BODY_HIT), _event(DuelEventTypes.DEFLECTION)], _live(), 3, MatchPhase.NO_WINNER), &"", "a body hit without a critical is also silent")
	assert_true(crowd.excitement < after_critical, "and ordinary contact decays rather than climbing")


func test_a_critical_during_cooldown_raises_intensity_and_does_not_shoot() -> void:
	var crowd := CrowdDirector.new()
	assert_eq(crowd.observe([_event(DuelEventTypes.CRITICAL_HIT)], _live(), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_CHEER, "the first critical cheers")
	var first := crowd.excitement
	assert_between(first, 0.2, 1.0, "and raised the meter")
	assert_eq(crowd.observe([_event(DuelEventTypes.CRITICAL_HIT)], _live(), 3, MatchPhase.NO_WINNER), &"", "a second tick of the same run does not shoot")
	assert_eq(crowd.excitement, first, "and does not add again")
	for _i in 8:
		crowd.observe([], _live(), 3, MatchPhase.NO_WINNER)
	var cooled := crowd.excitement
	assert_true(cooled < first, "fixture: empty ticks decayed the meter")
	assert_true(crowd.cooldown > 0, "fixture: the shot cooldown is still held")
	assert_eq(crowd.observe([_event(DuelEventTypes.CRITICAL_HIT)], _live(), 3, MatchPhase.NO_WINNER), &"", "a new critical during cooldown does not shoot")
	assert_true(crowd.excitement > cooled, "but it still raises intensity")
	assert_true(crowd.excitement <= 1.0, "inside the cap")


func test_a_kill_and_a_critical_are_one_strong_shot() -> void:
	var crowd := CrowdDirector.new()
	var cue := crowd.observe([
		_event(DuelEventTypes.BODY_HIT),
		_event(DuelEventTypes.CRITICAL_HIT),
		_event(DuelEventTypes.FIGHTER_KILLED),
		_event(DuelEventTypes.ROUND_ENDED, {DuelEventKeys.REASON: String(MatchPhase.REASON_KILL)}),
	], PackedInt32Array([1, 0]), 3, MatchPhase.NO_WINNER)
	assert_eq(cue, CrowdDirector.CUE_STRONG, "the kill is the one shot")
	assert_between(crowd.excitement, 0.4, 1.0, "from the finish class only")


func test_round_ended_never_selects_a_cue() -> void:
	var timeout := CrowdDirector.new()
	assert_eq(timeout.observe([_event(DuelEventTypes.ROUND_ENDED, {DuelEventKeys.REASON: String(MatchPhase.REASON_TIMEOUT)})], _live(), 3, MatchPhase.NO_WINNER), &"", "a timeout is silence")
	assert_eq(timeout.excitement, 0.0, "and does not raise intensity")
	var kill := CrowdDirector.new()
	assert_eq(kill.observe([
		_event(DuelEventTypes.FIGHTER_KILLED),
		_event(DuelEventTypes.ROUND_ENDED, {DuelEventKeys.REASON: String(MatchPhase.REASON_KILL)}),
	], PackedInt32Array([1, 0]), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_STRONG, "ROUND_ENDED beside a kill is still one shot")
	assert_eq(kill.observe([_event(DuelEventTypes.RING_OUT)], PackedInt32Array([1, 0]), 3, MatchPhase.NO_WINNER), &"", "a second terminal at those scores does not roar again")
	var ring := CrowdDirector.new()
	assert_eq(ring.observe([_event(DuelEventTypes.RING_OUT)], PackedInt32Array([0, 1]), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_STRONG, "a ring-out on a fresh director is that same strong class")


func test_a_clean_parry_cheers_and_a_weak_one_does_not() -> void:
	var crowd := CrowdDirector.new()
	assert_eq(crowd.observe([_event(DuelEventTypes.PARRY, {DuelEventKeys.MARGIN: 0.0})], _live(), 3, MatchPhase.NO_WINNER), &"", "no tempo is not a crowd beat")
	assert_eq(crowd.excitement, 0.0, "and does not raise intensity")
	assert_eq(crowd.observe([_event(DuelEventTypes.PARRY, {DuelEventKeys.MARGIN: 0.08})], _live(), 3, MatchPhase.NO_WINNER), &"", "a threshold parry is not the high end")
	assert_eq(crowd.observe([_event(DuelEventTypes.PARRY, {DuelEventKeys.MARGIN: 0.16})], _live(), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_CHEER, "a clean parry cheers")
	assert_between(crowd.excitement, 0.2, 1.0, "and raises the meter")


func test_set_point_and_set_win_and_first_to_one() -> void:
	var point := CrowdDirector.new()
	assert_eq(point.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_SETPOINT, "an earned set point plays on arrival")
	assert_eq(point.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), &"", "staying on that score does not cheer again")
	var held := CrowdDirector.new()
	assert_eq(held.observe([_event(DuelEventTypes.CRITICAL_HIT)], _live(), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_CHEER, "fixture: a critical starts cooldown")
	assert_eq(held.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), &"", "a set point on a higher class's cooldown is dropped")
	var heard := &""
	for _i in CrowdDirector.COOLDOWN_TICKS + 4:
		heard = held.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER)
		if heard != &"":
			break
	assert_eq(heard, &"", "and cooldown expiry does not play it later")
	var win := CrowdDirector.new()
	assert_eq(win.observe([_event(DuelEventTypes.FIGHTER_KILLED)], PackedInt32Array([2, 0]), 3, 0), CrowdDirector.CUE_VICTORY, "the set win outranks the kill")
	var peak := win.excitement
	assert_eq(win.observe([_event(DuelEventTypes.CRITICAL_HIT)], PackedInt32Array([2, 0]), 3, 0), &"", "and does not restart while the winner stays")
	assert_true(win.excitement < peak, "later observations decay even while the winner is still set")
	var training := CrowdDirector.new()
	assert_eq(training.observe([], PackedInt32Array([0, 0]), 1, MatchPhase.NO_WINNER), &"", "first-to-one at 0-0 is not a set point")
	assert_eq(training.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([0, 0]), 1, MatchPhase.NO_WINNER), &"", "and a contact is still silence")


func test_duplicate_terminals_at_the_same_score_are_one_shot() -> void:
	var crowd := CrowdDirector.new()
	assert_eq(crowd.observe([_event(DuelEventTypes.FIGHTER_KILLED)], PackedInt32Array([1, 0]), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_STRONG, "the first finish of a scoreline roars")
	assert_eq(crowd.observe([_event(DuelEventTypes.FIGHTER_KILLED)], PackedInt32Array([1, 0]), 3, MatchPhase.NO_WINNER), &"", "a lingering kill at those scores does not")
	assert_eq(crowd.observe([_event(DuelEventTypes.RING_OUT)], PackedInt32Array([1, 0]), 3, MatchPhase.NO_WINNER), &"", "nor a constructed ring-out at the same scores")
	assert_eq(crowd.observe([_event(DuelEventTypes.FIGHTER_KILLED)], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), CrowdDirector.CUE_STRONG, "a new scoreline may roar again")


func test_victory_intensity_decays_while_the_winner_stays() -> void:
	var crowd := CrowdDirector.new()
	assert_eq(crowd.observe([_event(DuelEventTypes.FIGHTER_KILLED)], PackedInt32Array([3, 0]), 3, 0), CrowdDirector.CUE_VICTORY, "fixture: victory fired once")
	assert_eq(crowd.excitement, CrowdDirector.STEP_VICTORY, "and sat at the cap")
	for _i in 8:
		assert_eq(crowd.observe([], PackedInt32Array([3, 0]), 3, 0), &"", "later ticks with the winner still set do not shoot")
	assert_true(crowd.excitement < CrowdDirector.STEP_VICTORY, "and the meter decays")


func test_a_new_director_after_victory_starts_ambient() -> void:
	var previous := CrowdDirector.new()
	previous.observe([_event(DuelEventTypes.FIGHTER_KILLED)], PackedInt32Array([3, 0]), 3, 0)
	assert_eq(previous.excitement, CrowdDirector.STEP_VICTORY, "fixture: the last match peaked")
	var next_match := CrowdDirector.new()
	assert_eq(next_match.excitement, 0.0, "a new match does not inherit that meter")
	assert_eq(next_match.observe([], PackedInt32Array([0, 0]), 3, MatchPhase.NO_WINNER), &"", "and does not shoot")


func test_a_quiet_stretch_returns_intensity_to_the_ambient_band() -> void:
	var crowd := CrowdDirector.new()
	crowd.observe([_event(DuelEventTypes.CRITICAL_HIT)], _live(), 3, MatchPhase.NO_WINNER)
	assert_true(crowd.excitement > 0.2, "fixture: the meter rose")
	var extra := 0
	for _i in 240:
		if crowd.observe([], _live(), 3, MatchPhase.NO_WINNER) != &"":
			extra += 1
	assert_eq(extra, 0, "decay emits nothing")
	assert_true(crowd.excitement < 0.15, "a few seconds of quiet sit in the ambient band")


func test_repeated_cheers_do_not_immediately_repeat_when_takes_exist() -> void:
	var audio := AudioDirector.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(audio)
	var first := load("res://assets/presentation/audio/crowd/cheer.mp3") as AudioStream
	var second := load("res://assets/presentation/audio/crowd/cheer_strong.mp3") as AudioStream
	assert_true(first != null and second != null and first != second, "fixture: two distinct recordings")
	var kit := PresentationKit.new()
	kit.audio_cues[PresentationKit.CUE_CROWD_CHEER] = [first, second]
	assert_true(audio.play_crowd_cue(kit, PresentationKit.CUE_CROWD_CHEER), "the first eligible cheer plays")
	assert_true(audio.crowd_shot_stream() == first, "it takes the first recording")
	assert_true(audio.play_crowd_cue(kit, PresentationKit.CUE_CROWD_CHEER), "a second eligible cheer plays")
	assert_true(audio.crowd_shot_stream() == second, "and does not immediately repeat")
	assert_true(audio.play_crowd_cue(kit, PresentationKit.CUE_CROWD_CHEER), "a third rotates")
	assert_true(audio.crowd_shot_stream() == first, "back to the first take")
	var one := PresentationKit.new()
	one.audio_cues[PresentationKit.CUE_CROWD_CHEER] = [first]
	assert_true(audio.play_crowd_cue(one, PresentationKit.CUE_CROWD_CHEER), "one take still plays")
	assert_true(audio.crowd_shot_stream() == first, "and that one take is the only choice")
	audio.free()


func test_body_severity_orders_the_bed_and_does_not_use_impulse() -> void:
	var tuning := StandardDuelRules.create().combat
	var light := _observe_level(_body(tuning.reference_severity * 0.2, "slash"), tuning)
	var middle := _observe_level(_body(tuning.reference_severity * 0.4, "slash"), tuning)
	var heavy := _observe_level(_body(tuning.reference_severity, "slash"), tuning)
	assert_eq(light, 0.0, "a scratch does not lift the bed")
	assert_eq(middle, 0.0, "an ordinary wound does not lift the bed")
	assert_true(heavy > 0.0 and heavy <= 1.0, "a reference wound does (%.3f)" % heavy)
	var graze := CrowdDirector.new()
	var cue := graze.observe([_body(tuning.reference_severity, "graze")], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, _reach(2.0))
	assert_eq(cue, &"", "a graze does not shoot")
	assert_eq(graze.excitement, 0.0, "and does not lift the bed")
	var impulse_only := _observe_level(_event(DuelEventTypes.BODY_HIT, {DuelEventKeys.IMPULSE: tuning.reference_impulse, DuelEventKeys.CONTACT_KIND: "slash"}), tuning)
	assert_eq(impulse_only, 0.0, "impulse without severity is not a body reading")


func test_steel_intensity_lifts_the_bed_without_a_shot() -> void:
	var tuning := StandardDuelRules.create().combat
	var light := CrowdDirector.new()
	var light_cue := light.observe([_blade(ContactResolver.CLASS_LIGHT, 1.0)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, _reach(2.0))
	assert_eq(light_cue, &"", "light steel does not shoot")
	assert_eq(light.excitement, 0.0, "and does not lift the bed")
	var solid := _observe_level(_blade(ContactResolver.CLASS_SOLID, 1.0), tuning)
	var strong := _observe_level(_blade(ContactResolver.CLASS_STRONG, 1.0), tuning)
	assert_eq(solid, 0.0, "an ordinary clash leaves the bed alone")
	assert_true(strong > 0.0, "a strong clash still lifts it")
	var shot := CrowdDirector.new()
	assert_eq(shot.observe([_blade(ContactResolver.CLASS_STRONG, 1.0)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, _reach(2.0)), &"", "steel still does not cheer")


func test_a_critical_does_not_add_the_body_lift() -> void:
	var tuning := StandardDuelRules.create().combat
	var crowd := CrowdDirector.new()
	var cue := crowd.observe([
		_body(tuning.reference_severity, "slash"),
		_event(DuelEventTypes.CRITICAL_HIT),
	], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, _reach(2.0))
	assert_eq(cue, CrowdDirector.CUE_CHEER, "the critical is the one shot")
	assert_eq(crowd.excitement, CrowdDirector.STEP_CRITICAL, "the body severity is not added on top")


func test_a_committed_whiff_gasps_in_measure_and_only_lifts_outside_it() -> void:
	var tuning := StandardDuelRules.create().combat
	var reach := _reach(2.0)
	var tap := CrowdDirector.new()
	assert_eq(tap.observe([_whiff(0.0)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), &"", "a tap miss is silence")
	assert_eq(tap.excitement, 0.0, "and does not lift the bed")
	var close := CrowdDirector.new()
	assert_eq(close.observe([_whiff(0.8)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), CrowdDirector.CUE_GASP, "a committed miss inside reach gasps")
	assert_eq(close.excitement, CrowdDirector.WHIFF_LEVEL, "at the whiff level")
	assert_true(CrowdDirector.WHIFF_LEVEL < CrowdDirector.STEP_FINISH, "which stays under a finish")
	assert_eq(close.observe([_whiff(0.8)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), &"", "cooldown holds the next gasp")
	for _i in CrowdDirector.COOLDOWN_TICKS:
		close.observe([], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach)
	assert_eq(close.observe([_whiff(0.8)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), &"", "the ordinary wait outlasts the class cooldown")
	var during := close.excitement
	var heavy_cue := close.observe([_body(tuning.reference_severity, "slash")], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach)
	assert_eq(heavy_cue, &"", "a heavy wound during that wait does not shout")
	assert_true(close.excitement > during, "but the bed may still rise")
	for _i in CrowdDirector.ORDINARY_COOLDOWN_TICKS:
		close.observe([], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach)
	assert_eq(close.observe([_whiff(0.8)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), CrowdDirector.CUE_GASP, "after the ordinary wait a committed miss may gasp again")
	var piled_window := CrowdDirector.new()
	var one := piled_window.observe([
		_whiff(0.8),
		_blade(ContactResolver.CLASS_SOLID, 1.0),
	], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach)
	assert_eq(one, CrowdDirector.CUE_GASP, "a whiff and a clash on one tick are one gasp")
	assert_eq(piled_window.observe([_whiff(0.8)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), &"", "and not a second shout on the next tick")
	var struck := CrowdDirector.new()
	assert_eq(struck.observe([
		_whiff(0.8),
		_body(tuning.reference_severity * 0.2, "slash"),
	], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), &"", "a scratch on that tick keeps the gasp silent")
	var through := CrowdDirector.new()
	assert_eq(through.observe([_whiff(0.8)], _live(), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach), CrowdDirector.CUE_GASP, "fixture: an ordinary gasp is waiting")
	assert_eq(through.observe([], PackedInt32Array([3, 0]), 3, 0, tuning, 1.0, reach), CrowdDirector.CUE_VICTORY, "a set win still speaks during that wait")
	var far := CrowdDirector.new()
	assert_eq(far.observe([_whiff(0.8)], _live(), 3, MatchPhase.NO_WINNER, tuning, 5.0, reach), &"", "the same miss outside reach does not gasp")
	assert_eq(far.excitement, CrowdDirector.WHIFF_LEVEL, "but it still lifts the bed")
	var punish := CrowdDirector.new()
	var piled := punish.observe([
		_whiff(0.8),
		_event(DuelEventTypes.FIGHTER_KILLED),
	], PackedInt32Array([1, 0]), 3, MatchPhase.NO_WINNER, tuning, 1.0, reach)
	assert_eq(piled, CrowdDirector.CUE_STRONG, "a kill on that tick is the shot")
	assert_eq(punish.excitement, CrowdDirector.STEP_FINISH, "and the whiff is not stacked onto it")


func test_a_real_meeting_and_a_far_whiff_use_the_shipping_scale() -> void:
	var rules := StandardDuelRules.create()
	var meet := SimRunner.create(rules, 4)
	meet.skip_intro()
	for _i in 90:
		meet.push(PlayerCommand.create(meet.state.tick, 0.0, 1.0, true, false), PlayerCommand.create(meet.state.tick, 0.0, 1.0))
	meet.push(PlayerCommand.create(meet.state.tick, 0.0, 1.0, false, true), PlayerCommand.idle(meet.state.tick))
	for _i in 40:
		meet.push(PlayerCommand.idle(meet.state.tick), PlayerCommand.idle(meet.state.tick))
	assert_true(meet.is_sound(), meet.violation_summary())
	var light: DuelEvent = null
	var heavy: DuelEvent = null
	for event in meet.events:
		if event.type != DuelEventTypes.BODY_HIT:
			continue
		if light == null or event.number(DuelEventKeys.SEVERITY) < light.number(DuelEventKeys.SEVERITY):
			light = event
		if heavy == null or event.number(DuelEventKeys.SEVERITY) > heavy.number(DuelEventKeys.SEVERITY):
			heavy = event
	assert_true(light != null and heavy != null and heavy != light, "fixture: the meeting produced a light hit and a heavier one")
	var reach := _reach(WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)))
	var light_bed := _observe_level(light, rules.combat, 1.0, reach)
	var heavy_bed := _observe_level(heavy, rules.combat, 1.0, reach)
	assert_true(heavy_bed > light_bed, "the heavier wound from the duel sits higher (%.3f > %.3f)" % [heavy_bed, light_bed])
	var far := SimRunner.create(rules, 4)
	far.skip_intro()
	for _i in 50:
		far.push(PlayerCommand.create(far.state.tick, 0.0, 0.0, true, false), PlayerCommand.idle(far.state.tick))
	far.push(PlayerCommand.create(far.state.tick, 0.0, 0.0, false, true), PlayerCommand.idle(far.state.tick))
	for _i in 120:
		far.push(PlayerCommand.idle(far.state.tick), PlayerCommand.idle(far.state.tick))
	var whiff: DuelEvent = null
	for event in far.events:
		if event.type == DuelEventTypes.ATTACK_WHIFFED:
			whiff = event
	var apart := DuelGeometry.distance(far.state.fighter(0), far.state.fighter(1))
	assert_true(far.is_sound(), far.violation_summary())
	assert_true(whiff != null, "fixture: the far swing whiffed")
	assert_true(whiff.number(DuelEventKeys.CHARGE) >= CrowdDirector.WHIFF_COMMITTED_CHARGE, "and the hold was committed (%.2f)" % whiff.number(DuelEventKeys.CHARGE))
	assert_true(apart > reach[0], "from outside strike reach")
	var crowd := CrowdDirector.new()
	var cue := crowd.observe([whiff], _live(), 3, MatchPhase.NO_WINNER, rules.combat, apart, reach)
	assert_eq(cue, &"", "that miss does not gasp")
	assert_true(crowd.excitement > 0.0 and crowd.excitement < CrowdDirector.STEP_FINISH, "and the lift stays under a finish")


func _body(severity: float, kind: String) -> DuelEvent:
	return _event(DuelEventTypes.BODY_HIT, {DuelEventKeys.SEVERITY: severity, DuelEventKeys.CONTACT_KIND: kind})


func _blade(band: StringName, intensity: float) -> DuelEvent:
	return _event(DuelEventTypes.BLADE_CONTACT, {DuelEventKeys.CONTACT_CLASS: String(band), DuelEventKeys.INTENSITY: intensity})


func _whiff(charge: float) -> DuelEvent:
	return _event(DuelEventTypes.ATTACK_WHIFFED, {DuelEventKeys.CHARGE: charge})


func _reach(span: float) -> PackedFloat32Array:
	return PackedFloat32Array([span, span])


func _observe_level(event: DuelEvent, tuning: CombatTuning, distance: float = 1.0, reach: PackedFloat32Array = PackedFloat32Array()) -> float:
	var span := reach if not reach.is_empty() else _reach(2.0)
	var crowd := CrowdDirector.new()
	crowd.observe([event], _live(), 3, MatchPhase.NO_WINNER, tuning, distance, span)
	return crowd.excitement


func test_the_bed_and_one_reaction_play_on_the_crowd_bus() -> void:
	var rules := StandardDuelRules.create()
	var root := Node3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(root)
	var camera := DuelCameraRig.new()
	root.add_child(camera)
	camera.configure(RiposteKits.camera_profile())
	var state := DuelSetup.new_state(rules, 1)
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), rules)
	var presenter := MatchPresenter.create(kits, PresentationOptions.new(), camera, rules.platform_radius, rules.edge_warning_inset, SnapshotProjector.project(state, rules))
	root.add_child(presenter)
	var audio := presenter.audio()
	assert_true(audio.is_crowd_bed_playing(), "the bed is playing")
	var bed := _player_for(audio, audio.crowd_bed_stream())
	assert_true(bed != null and bed.bus == AudioBuses.CROWD, "on the Crowd bus")
	assert_true((bed.stream as AudioStreamMP3).loop, "and it loops")
	assert_near(audio.crowd_bed_volume_db(), -18.0, 0.01, "intensity 0 sits on the ambient trim")
	var written := audio.crowd_bed_volume_db()
	presenter.play_crowd(&"", 0, 0.01)
	presenter.render(0.0, 1.0)
	assert_eq(audio.crowd_bed_volume_db(), written, "a tiny intensity change does not rewrite volume_db")
	presenter.play_crowd(&"", 0, 1.0)
	presenter.render(0.0, 10.0)
	assert_near(audio.crowd_bed_volume_db(), -10.0, 0.01, "intensity 1 sits on the momentum trim")
	presenter.play_crowd(&"cheer", 0)
	var shot := _player_for(audio, audio.crowd_shot_stream())
	assert_eq(audio.crowd_shot_stream().resource_path.get_file(), "cheer.mp3", "the light cheer is the shot")
	assert_true(shot != null and shot.bus == AudioBuses.CROWD and shot.playing, "one reaction, on Crowd")
	presenter.play_crowd(CrowdDirector.CUE_GASP, 0)
	assert_eq(audio.crowd_shot_stream().resource_path.get_file(), "gasp.mp3", "a committed miss uses the gasp")
	presenter.play_crowd(CrowdDirector.CUE_STRONG, 0)
	assert_eq(audio.crowd_shot_stream().resource_path.get_file(), "cheer_strong.mp3", "a stronger reaction replaces it")
	assert_eq(_playing_shots(audio, audio.crowd_shot_stream()), 1, "and does not stack a second voice")
	var strong := audio.crowd_shot_stream()
	presenter.play_crowd(&"no-such-cue", 0)
	assert_true(audio.crowd_shot_stream() == strong, "an unknown cue leaves the shot alone")
	var fighter := kits.combatant(0).fighter
	var chant := fighter.crowd_chant
	fighter.crowd_chant = null
	presenter.play_crowd(&"victory", 0)
	var fallback := audio.crowd_shot_stream()
	fighter.crowd_chant = chant
	assert_eq(fallback.resource_path.get_file(), "victory.mp3", "a fighter without a chant gets the generic roar")
	presenter.play_crowd(&"victory", 0)
	assert_eq(audio.crowd_shot_stream().resource_path.get_file(), "wolf_chant.mp3", "Wolf's chant replaces that roar")
	var sting := audio.get_node(AudioDirector.PLAYER_STING) as AudioStreamPlayer
	presenter.play_set_horn()
	assert_true(sting.playing and sting.stream is AudioStreamMP3 and not (sting.stream as AudioStreamMP3).loop, "the horn stays one blast, not a loop")
	assert_true(sting.stream.resource_path.get_file().begins_with("match_horn"), "the set horn is the arena's")
	var horn_length := sting.stream.get_length()
	assert_true(horn_length > 0.0 and horn_length < AudioDirector.HORN_SECONDS, "fixture: the take is shorter than the hold")
	assert_near(sting.pitch_scale, horn_length / AudioDirector.HORN_SECONDS, 0.001, "that one blast is slowed to six seconds")
	assert_eq(sting.bus, AudioBuses.MUSIC, "on the sting's Music bus")
	assert_false(audio.is_character_call_playing(), "and it is not Wolf's howl")
	presenter.detach_and_dispose()
	assert_false(audio.is_crowd_bed_playing(), "disposing the presenter stops that bed")
	var next := MatchPresenter.create(kits, PresentationOptions.new(), camera, rules.platform_radius, rules.edge_warning_inset, SnapshotProjector.project(state, rules))
	root.add_child(next)
	assert_true(next.audio().is_crowd_bed_playing(), "a new presenter starts its own bed")
	assert_near(next.audio().crowd_bed_volume_db(), -18.0, 0.01, "at ambient, not the previous match's trim")
	assert_false(audio.is_crowd_bed_playing(), "the disposed director stays silent")
	root.queue_free()


func test_the_author_plan_matches_the_kits_and_does_not_drift() -> void:
	var first := AudioKitPlan.arena_specs()
	var second := AudioKitPlan.arena_specs()
	assert_eq(first.size(), second.size(), "a second read is the same map")
	for cue: Variant in first:
		assert_eq(first[cue], second[cue], "cue %s is stable" % cue)
	var arena := load(AudioKitPlan.ARENA_KIT) as PresentationKit
	for cue: Variant in first:
		var stream := arena.stream_for(StringName(str(cue)))
		var stem := str(first[cue]).get_slice(":", 1)
		assert_true(stream != null, "the arena kit has %s" % cue)
		assert_true(stream.resource_path.get_file().begins_with(stem), "%s points at %s" % [cue, stem])
	assert_eq(arena.variant_count(PresentationKit.CUE_CROWD_CHEER), 1, "cheer is one take until a second recording is authored")
	assert_eq(arena.variant_count(PresentationKit.CUE_CROWD_STRONG), 1, "strong is one take until a second recording is authored")
	assert_eq(arena.variant_count(PresentationKit.CUE_CROWD_SETPOINT), 1, "set point is one take until a second recording is authored")
	assert_eq(arena.variant_count(PresentationKit.CUE_CROWD_VICTORY), 1, "victory is one take until a second recording is authored")
	assert_eq(arena.variant_count(PresentationKit.CUE_CROWD_GASP), 1, "the gasp is one take")
	var fighter := load(AudioKitPlan.FIGHTER_KIT) as PresentationKit
	var intro_name := fighter.intro.display_name
	var intro_spoken := fighter.intro.spoken_name
	var symbol := fighter.symbol
	var victory_name := fighter.victory.display_name if fighter.victory != null else ""
	var problems := PackedStringArray()
	AudioKitPlan.apply_fighter(fighter, problems)
	AudioKitPlan.apply_arena(arena, problems)
	AudioKitPlan.apply_fighter(fighter, problems)
	AudioKitPlan.apply_arena(arena, problems)
	assert_eq(problems.size(), 0, "the plan finds every take")
	assert_eq(fighter.intro.display_name, intro_name, "a second apply keeps the intro name")
	assert_eq(fighter.intro.spoken_name, intro_spoken, "and the intro's spoken line")
	assert_true(fighter.symbol == symbol, "and the mark")
	assert_eq(fighter.victory.display_name if fighter.victory != null else "", victory_name, "and the victory card's name")
	assert_true(fighter.character_call.resource_path.get_file().begins_with("wolf_howl"), "the howl is the character call")
	assert_true(fighter.crowd_chant.resource_path.get_file().begins_with("wolf_chant"), "the chant is the name call")
	var announcer := load(AudioKitPlan.ANNOUNCER_KIT) as AnnouncerKit
	var caption := announcer.versus_caption
	AudioKitPlan.apply_announcer(announcer, problems)
	AudioKitPlan.apply_announcer(announcer, problems)
	assert_eq(announcer.versus_caption, caption, "the announcer's caption survives")
	assert_true(announcer.fight != null and announcer.match_numbers.size() == AudioKitPlan.MATCH_LINES, "the round calls stay")
	var ui := load(AudioKitPlan.UI_THEME_KIT) as UiThemeKit
	AudioKitPlan.apply_ui(ui, problems)
	AudioKitPlan.apply_ui(ui, problems)
	assert_eq(ui.theme_id, &"ui.standard", "the ui theme id stays")
	assert_true(ui.confirm.size() > 0 and ui.back.size() > 0 and ui.hover.size() > 0, "and its menu sounds")
	var weapon := load(AudioKitPlan.WEAPON_KIT) as PresentationKit
	var victory := load(AudioKitPlan.VICTORY_PROFILE) as FighterVictoryProfile
	var victory_title := victory.title
	AudioKitPlan.apply_weapon(weapon, problems)
	AudioKitPlan.apply_weapon(weapon, problems)
	AudioKitPlan.apply_victory(victory, problems)
	AudioKitPlan.apply_victory(victory, problems)
	assert_eq(victory.title, victory_title, "the victory title survives")
	assert_true(weapon.stream_for(PresentationKit.CUE_SWING) != null, "the swing cue survives")
	assert_true(victory.announcer_line != null, "the winner line survives")
	assert_true(arena.stream_for(PresentationKit.CUE_MATCH_HORN) != null, "and the match horn stays on the arena")


func _player_for(node: Node, stream: AudioStream) -> AudioStreamPlayer:
	if node is AudioStreamPlayer and (node as AudioStreamPlayer).stream == stream:
		return node as AudioStreamPlayer
	for child in node.get_children():
		var found := _player_for(child, stream)
		if found != null:
			return found
	return null


func _playing_shots(node: Node, stream: AudioStream) -> int:
	var count := 0
	if node is AudioStreamPlayer:
		var player := node as AudioStreamPlayer
		if player.playing and player.stream == stream:
			count += 1
	for child in node.get_children():
		count += _playing_shots(child, stream)
	return count


func test_the_horn_fires_once_for_a_killing_set_win() -> void:
	var horn := SetWinningHorn.new()
	assert_false(horn.consider(MatchPhase.NO_WINNER, FighterState.Terminal.KILLED), "a live round is silent")
	assert_false(horn.consider(0, FighterState.Terminal.RING_OUT), "a ring-out does not take the horn")
	assert_true(horn.consider(0, FighterState.Terminal.KILLED), "the killing set win plays it")
	assert_false(horn.consider(0, FighterState.Terminal.KILLED), "a second observer does not replay it")
