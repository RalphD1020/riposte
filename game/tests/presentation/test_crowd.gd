extends TestCase

## PRES-CROWD: crowd cues come from existing events, a set win outranks a
## clash, and the cooldown holds the next ordinary reaction.
##
## See also: /docs/concepts/presentation.md


func _init() -> void:
	suite_name = "PRES-CROWD"


func _event(type: StringName) -> DuelEvent:
	return DuelEvent.create(type, 0, 1)


func test_a_set_winning_kill_is_the_loudest_cue() -> void:
	var crowd := CrowdDirector.new()
	var cue := crowd.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([2, 0]), 3, 0)
	assert_eq(cue, &"victory", "the set win outranks the clash")


func test_an_ordinary_round_does_not_roar() -> void:
	var crowd := CrowdDirector.new()
	var cue := crowd.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([0, 0]), 3, MatchPhase.NO_WINNER)
	assert_eq(cue, &"murmur", "the first light exchange is only a murmur")
	assert_eq(crowd.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([0, 0]), 3, MatchPhase.NO_WINNER), &"", "the cooldown holds the next one")


func test_a_stronger_cue_speaks_over_a_minor_cooldown_and_victory_once() -> void:
	var crowd := CrowdDirector.new()
	assert_eq(crowd.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([0, 0]), 3, MatchPhase.NO_WINNER), &"murmur", "fixture: a light contact murmurs")
	assert_eq(crowd.observe([_event(DuelEventTypes.PARRY)], PackedInt32Array([0, 0]), 3, MatchPhase.NO_WINNER), &"strong", "a parry is not dropped for that murmur")
	assert_eq(crowd.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), &"", "reaching the set point does not talk over that parry")
	var heard := &""
	for _i in CrowdDirector.COOLDOWN_TICKS:
		heard = crowd.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER)
		if heard != &"":
			break
	assert_eq(heard, &"setpoint", "the set point plays once, after the parry, while the score is still there")
	assert_eq(crowd.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), &"", "staying on that score does not cheer again")
	var point := CrowdDirector.new()
	assert_eq(point.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([0, 0]), 3, MatchPhase.NO_WINNER), &"murmur", "fixture: another light contact")
	assert_eq(point.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), &"setpoint", "a set point speaks over a murmur")
	assert_eq(point.observe([], PackedInt32Array([2, 0]), 3, MatchPhase.NO_WINNER), &"", "and only on the tick the score arrives")
	var win := CrowdDirector.new()
	assert_eq(win.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([2, 0]), 3, 0), &"victory", "the set win plays")
	assert_eq(win.observe([_event(DuelEventTypes.PARRY)], PackedInt32Array([2, 0]), 3, 0), &"", "and does not restart on the next tick")


func test_first_to_one_is_not_a_set_point() -> void:
	var crowd := CrowdDirector.new()
	assert_eq(crowd.observe([], PackedInt32Array([0, 0]), 1, MatchPhase.NO_WINNER), &"", "training opens at zero, which is not a set point")
	assert_eq(crowd.observe([_event(DuelEventTypes.BLADE_CONTACT)], PackedInt32Array([0, 0]), 1, MatchPhase.NO_WINNER), CrowdDirector.CUE_MURMUR, "a light contact is still only a murmur")


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
	presenter.play_crowd(&"cheer", 0)
	var shot := _player_for(audio, audio.crowd_shot_stream())
	assert_eq(audio.crowd_shot_stream().resource_path.get_file(), "cheer.mp3", "the light cheer is the shot")
	assert_true(shot != null and shot.bus == AudioBuses.CROWD and shot.playing, "one reaction, on Crowd")
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
	assert_true(arena.stream_for(PresentationKit.CUE_CROWD_GASP) == null, "the gasp is not an active cue")
	assert_true(FileAccess.file_exists(AudioKitPlan.GASP_UNUSED), "the unused file stays on disk")
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
	assert_true(victory.fanfare != null and victory.announcer_line != null, "the horn and the winner line survive")


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
