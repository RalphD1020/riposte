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
	assert_false(director.audio().is_sting_playing(), "the lock does not start the set horn")
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
	assert_false(director.audio().is_sting_playing() or director.audio().is_voice_playing(), "and nothing sounds in their place")
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
