extends TestCase

## PRES-VICTORY: the set winner's showcase sounds each beat exactly once, its
## charge is a held voice released on the lock, the arena horn is not this
## cinematic, and a missing take never holds the timeline (PRES-VICTORY-001,
## PRES-KIT-001 loop families).
##
## Implements: /spec/invariants.md#pres-victory-001
## See also: /docs/concepts/presentation.md

const FRAME := 1.0 / 60.0

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-VICTORY"
	_rules = StandardDuelRules.create()


func _combatant(line_present: bool = true) -> CombatantPresentationKit:
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	var combatant := kits.combatant(0)
	if line_present:
		return combatant
	var fighter := combatant.fighter.duplicate() as PresentationKit
	var victory := combatant.victory().duplicate() as FighterVictoryProfile
	victory.announcer_line = null
	fighter.victory = victory
	return CombatantPresentationKit.of(fighter, combatant.weapon, combatant.fighter_skin, combatant.weapon_skin)


func _horn() -> AudioStream:
	var arena := load(AudioKitPlan.ARENA_KIT) as PresentationKit
	return arena.stream_for(PresentationKit.CUE_MATCH_HORN)


func _director(combatant: CombatantPresentationKit) -> VictoryDirector:
	var director := VictoryDirector.create(combatant, DuelSide.Id.LIGHT_SOUTH, _rules.combatant(0).fighter.push_radius, _rules.combatant(0).weapon.blade_base_radius, _rules.combatant(0).weapon.tip_radius)
	(Engine.get_main_loop() as SceneTree).root.add_child(director)
	return director


func _count(director: VictoryDirector, stream: AudioStream) -> int:
	var count := 0
	for played in director.audio().history:
		if played == stream:
			count += 1
	return count


func _run(director: VictoryDirector, frames: int) -> void:
	for _i in frames:
		director.advance(FRAME)


## The show is simulated time on the profile. The suite's manifest budget is
## the wall-clock of this file. They are not the same interval.
func test_the_show_is_simulated_time_and_not_the_harness_budget() -> void:
	var director := _director(_combatant())
	var profile := director.profile()
	assert_near(profile.interactive_time, 2.2, 1e-6, "the authored show ends at 2.2 s of simulated time")
	_run(director, ceili(profile.interactive_time / FRAME))
	assert_true(director.elapsed() + 1e-6 >= profile.interactive_time, "the director was stepped to that time")
	director.free()


func test_every_beat_sounds_exactly_once_over_a_long_showcase() -> void:
	var combatant := _combatant()
	var director := _director(combatant)
	var profile := director.profile()
	assert_true(profile.announcer_line != null and _horn() != null, "fixture: Wolf has a winner line and the arena has a horn")
	assert_eq(_count(director, _horn()), 0, "fixture: the showcase has not played the arena horn")
	## 300 frames (5 s) runs well past the interactive time into the results.
	_run(director, 300)
	assert_false(director.is_cinematic(), "the showcase reached its results")
	assert_eq(_count(director, _horn()), 0, "the showcase does not play the arena horn")
	assert_eq(_count(director, profile.announcer_line), 1, "the winner line played exactly once")
	assert_eq(_count(director, combatant.fighter.character_call), 1, "the howl plays once under that line")
	assert_eq(director.fired_beats(), VictoryDirector.Beat.size(), "every beat fired")
	## The results screen can stay up indefinitely: nothing replays.
	_run(director, 600)
	assert_eq(_count(director, _horn()), 0, "a long results screen never plays the arena horn")
	assert_eq(_count(director, profile.announcer_line), 1, "or the line")
	assert_eq(_count(director, combatant.fighter.character_call), 1, "or the howl")
	assert_eq(_count(director, profile.sting), 1, "or the sting")
	director.free()


func test_the_charge_is_held_through_the_gather_and_released_on_the_lock() -> void:
	var director := _director(_combatant())
	var profile := director.profile()
	assert_true(profile.charge_lock_time > profile.charge_start_time, "fixture: the gather has length")
	assert_false(director.audio().is_tension_held(VictoryDirector.CHARGE_SLOT), "fixture: no charge before the gather")
	var mid := (profile.charge_start_time + profile.charge_lock_time) * 0.5
	_run(director, ceili(mid / FRAME))
	assert_true(director.audio().is_tension_held(VictoryDirector.CHARGE_SLOT), "the charge is held through the gather")
	_run(director, ceili((profile.charge_lock_time - mid) / FRAME) + 2)
	assert_false(director.audio().is_tension_held(VictoryDirector.CHARGE_SLOT), "the lock releases it — a looping stream never outlives the gather")
	assert_eq(_count(director, _horn()), 0, "the lock does not start the set horn")
	assert_eq(_count(director, profile.sting), 1, "the sting started once with the showcase, not on the lock")
	_run(director, 600)
	assert_false(director.audio().is_tension_held(VictoryDirector.CHARGE_SLOT), "nothing restarts the charge afterwards")
	director.free()


## The fighter call and the announcer are two Voice channels. Starting one
## does not stop or replace the other; skip fires both remaining beats in
## one frame and they stay concurrent.
func test_the_howl_and_the_announcer_play_together() -> void:
	var combatant := _combatant()
	var director := _director(combatant)
	var profile := director.profile()
	var howl := combatant.fighter.character_call
	assert_true(profile.announcer_line != null and howl != null, "fixture: Wolf has a winner line and a howl")
	director.finish()
	var audio := director.audio()
	var announcer := audio.get_node(AudioDirector.PLAYER_ANNOUNCER) as AudioStreamPlayer
	var fighter := audio.get_node(AudioDirector.PLAYER_FIGHTER) as AudioStreamPlayer
	assert_true(announcer != null and fighter != null and announcer != fighter, "two independently owned Voice players")
	assert_eq(announcer.bus, AudioBuses.VOICE, "the announcer is on Voice")
	assert_eq(fighter.bus, AudioBuses.VOICE, "the fighter call is on Voice")
	assert_true(audio.is_voice_playing(), "the announcer is playing")
	assert_true(audio.is_character_call_playing(), "and the howl is playing with it")
	assert_eq(audio.announcer_stream(), profile.announcer_line, "the announcer still holds its line")
	assert_eq(audio.character_call_stream(), howl, "the fighter still holds its call")
	assert_eq(announcer.stream, profile.announcer_line, "starting the howl did not replace the announcer stream")
	assert_eq(fighter.stream, howl, "starting the announcer did not replace the howl stream")
	assert_true(announcer.playing and fighter.playing, "both channels are active at once")
	assert_eq(announcer.volume_db, AudioDirector.ANNOUNCER_GAIN_DB, "the announcer is boosted")
	assert_eq(fighter.volume_db, AudioDirector.CALL_TRIM_DB, "the howl is trimmed under that line")
	assert_true(fighter.volume_db <= announcer.volume_db - 20.0, "the line stays well in front of the howl")
	var sting := audio.get_node(AudioDirector.PLAYER_STING) as AudioStreamPlayer
	assert_true(sting != null and sting != announcer and sting != fighter, "the sting has its own player")
	assert_false(sting.playing, "a skip stops the sting instead of leaving it running")
	assert_eq(_count(director, profile.sting), 1, "after the one start")
	director.free()


func test_skipping_twice_or_pausing_replays_nothing() -> void:
	var director := _director(_combatant())
	var profile := director.profile()
	_run(director, 30)
	assert_true(director.is_cinematic(), "fixture: mid-cinematic")
	director.finish()
	director.finish()
	assert_eq(_count(director, _horn()), 0, "a skip does not play the arena horn")
	assert_eq(_count(director, profile.announcer_line), 1, "and the line once")
	assert_eq(_count(director, profile.sting), 1, "the sting is not started again")
	assert_false(director.audio().is_sting_playing(), "a skip stops the sting without waiting for finished")
	assert_false(director.audio().is_tension_held(VictoryDirector.CHARGE_SLOT), "a skip never leaves the charge held")
	## A paused screen advances by zero; a resume continues where it was.
	for _i in 120:
		director.advance(0.0)
	_run(director, 120)
	assert_eq(_count(director, _horn()), 0, "pause and resume do not play the arena horn")
	director.free()


func test_a_new_showcase_plays_its_beats_again() -> void:
	var first := _director(_combatant())
	_run(first, 300)
	var line := first.profile().announcer_line
	assert_eq(_count(first, line), 1, "fixture: the first set's line played once")
	first.free()
	var second := _director(_combatant())
	assert_eq(_count(second, line), 0, "a rematch's showcase starts fresh")
	_run(second, 300)
	assert_eq(_count(second, line), 1, "and plays its line once")
	second.free()


func test_a_missing_take_never_holds_the_timeline() -> void:
	var director := _director(_combatant(false))
	var captions: Array[String] = []
	director.audio().caption_requested.connect(func(text: String, _seconds: float) -> void: captions.append(text))
	var cards := [0]
	director.card_requested.connect(func(_name: String, _title: String) -> void: cards[0] += 1)
	assert_true(director.profile().announcer_line == null, "fixture: the winner line is missing")
	_run(director, 300)
	assert_false(director.is_cinematic(), "the results still arrive")
	assert_eq(cards[0], 1, "the card still shows, once")
	assert_eq(captions, [director.profile().announcer_caption] as Array[String], "the winner line still reads as a caption, once")
	assert_false(director.audio().is_voice_playing(), "a missing line does not invent a voice")
	assert_eq(_count(director, _horn()), 0, "and the horn stays out")
	director.free()


func test_leaving_stops_every_voice() -> void:
	var director := _director(_combatant())
	var mid := (director.profile().charge_start_time + director.profile().charge_lock_time) * 0.5
	_run(director, ceili(mid / FRAME))
	assert_true(director.audio().is_any_playing(), "fixture: the charge is sounding")
	director.dispose()
	assert_false(director.audio().is_any_playing(), "dispose silences every family, holds included")
	director.free()


## Loop families across every authored kit: one-shot lines and stings never
## loop; only held cues (charge, bind) and music may.
func test_one_shot_streams_never_loop() -> void:
	var catalog := RiposteKits.build_catalog()
	var kits := DuelKits.resolve(catalog, _rules)
	var announcer := RiposteKits.announcer()
	var one_shots: Array[AudioStream] = [announcer.versus, announcer.sting, announcer.fight]
	one_shots.append_array(announcer.match_numbers)
	var victory := kits.combatant(0).victory()
	one_shots.append(victory.announcer_line)
	one_shots.append(victory.sting)
	one_shots.append(_horn())
	var checked := 0
	for stream in one_shots:
		if stream == null:
			continue
		checked += 1
		assert_false(bool(stream.get("loop")), "%s is a one-shot and must not loop" % stream.resource_path)
	assert_true(checked >= 6, "fixture: the announcer and victory takes are authored (%d checked)" % checked)
	var held := kits.weapon.stream_for(PresentationKit.CUE_CHARGE, 0)
	assert_true(held != null and bool(held.get("loop")), "the held charge loops — it has an owner that releases it")


## The announcer stays on Voice. The sting is this director's Music player,
## already started, and the two overlap.
func test_the_announcer_and_the_sting_play_together() -> void:
	var combatant := _combatant()
	var director := _director(combatant)
	var profile := director.profile()
	_run(director, ceili(profile.announcer_time / FRAME) + 2)
	var audio := director.audio()
	var voice := audio.get_node(AudioDirector.PLAYER_ANNOUNCER) as AudioStreamPlayer
	var sting := audio.get_node(AudioDirector.PLAYER_STING) as AudioStreamPlayer
	assert_true(voice != null and sting != null and voice != sting, "the line and the sting player are different")
	assert_eq(voice.bus, AudioBuses.VOICE, "the announcer stays on Voice")
	assert_eq(sting.bus, AudioBuses.MUSIC, "the sting stays on Music")
	assert_true(voice.playing, "the winner line is playing")
	assert_true(sting.playing, "and the sting is playing with it")
	assert_eq(voice.stream, profile.announcer_line, "the voice player is the winner line")
	assert_eq(sting.stream, profile.one_shot_sting(), "the sting player is the winner's one-shot")
	assert_eq(_count(director, profile.sting), 1, "the sting started once")
	assert_eq(_count(director, profile.announcer_line), 1, "and so did the line")
	assert_true(voice.volume_db > sting.volume_db, "the line is louder than the sting")
	director.free()


## The assigned file is the imported stand-in. The music player is what plays it.
func test_the_stand_in_is_the_real_stream() -> void:
	var profile := _combatant().victory()
	var sting := profile.one_shot_sting()
	assert_true(sting != null, "fixture: Wolf has a one-shot sting")
	assert_eq(sting.resource_path, RiposteKits.VICTORY_STING_STAND_IN, "the player is holding the assigned file")
	assert_near(sting.get_length(), 6.5, 1.0, "Wolf's victory theme is about five seconds")


func test_a_silent_profile_does_not_keep_the_previous_sting() -> void:
	var first := _director(_combatant())
	assert_true(first.audio().is_sting_playing(), "fixture: Wolf's showcase starts its sting")
	first.free()
	var second := _director(_with_sting(null))
	assert_false(second.audio().is_sting_playing(), "a profile without a sting stays silent")
	assert_true(second.profile().one_shot_sting() == null, "and it has nothing to start")
	second.free()


func test_the_sting_plays_once_and_a_skip_stops_it() -> void:
	var combatant := _combatant()
	var director := _director(combatant)
	assert_eq(_count(director, combatant.victory().sting), 1, "the showcase starts the sting once")
	assert_eq(_count(director, _horn()), 0, "and not the match horn")
	assert_true(director.audio().is_sting_playing(), "its music player is the sting")
	director.finish()
	director.finish()
	assert_eq(_count(director, combatant.victory().sting), 1, "a skip does not start another")
	assert_false(director.audio().is_sting_playing(), "and it stops the one that was playing")
	director.free()


## Emitting `finished` proves the end handler. It does not prove the mixer
## played the file to the end.
func test_a_finished_signal_ends_the_sting_once() -> void:
	var director := _director(_combatant())
	var player := director.audio().get_node(AudioDirector.PLAYER_STING) as AudioStreamPlayer
	assert_true(player.playing, "fixture: the sting is up")
	player.finished.emit()
	player.finished.emit()
	assert_eq(_count(director, director.profile().sting), 1, "a finished signal does not start the sting again")
	director.finish()
	assert_eq(_count(director, director.profile().sting), 1, "and a skip after that does not either")
	assert_false(director.audio().is_sting_playing(), "the player is stopped")
	director.free()


func test_a_missing_or_looping_sting_is_not_a_one_shot() -> void:
	var missing := _with_sting(null)
	assert_true(missing.victory().one_shot_sting() == null, "an unset sting is not played")
	var looped := AudioStreamWAV.new()
	looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
	var refused := _with_sting(looped)
	assert_true(refused.victory().one_shot_sting() == null, "a looping stream is not played")
	var director := _director(refused)
	assert_false(director.audio().is_sting_playing(), "and the showcase does not start it")
	director.free()


func test_two_showcases_do_not_leave_a_sting_player() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var before := _named(tree.root, AudioDirector.PLAYER_STING)
	var first := _director(_combatant())
	var second := _director(_combatant())
	assert_eq(_named(tree.root, AudioDirector.PLAYER_STING) - before, 2, "each showcase owns one sting player")
	first.free()
	second.free()
	assert_eq(_named(tree.root, AudioDirector.PLAYER_STING), before, "freeing both showcases removes both players")


func _with_sting(stream: AudioStream) -> CombatantPresentationKit:
	var combatant := _combatant()
	var fighter := combatant.fighter.duplicate() as PresentationKit
	var victory := combatant.victory().duplicate() as FighterVictoryProfile
	victory.sting = stream
	fighter.victory = victory
	return CombatantPresentationKit.of(fighter, combatant.weapon, combatant.fighter_skin, combatant.weapon_skin)


func _named(node: Node, node_name: String) -> int:
	var count := 0
	if String(node.name) == node_name:
		count += 1
	for child in node.get_children():
		count += _named(child, node_name)
	return count
