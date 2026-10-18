extends TestCase

## PRES-VICTORY: the set winner's showcase sounds each beat exactly once, its
## charge is a held voice released on the lock, the fanfare has its own Music
## voice, and a missing take never holds the timeline (PRES-VICTORY-001,
## PRES-KIT-001 loop families).
##
## Implements: /spec/invariants.md#pres-victory-001
## See also: /docs/concepts/presentation.md

const FRAME := 1.0 / 60.0

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-VICTORY"
	_rules = StandardDuelRules.create()


func _combatant(fanfare_present: bool = true, line_present: bool = true) -> CombatantPresentationKit:
	var kits := DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	var combatant := kits.combatant(0)
	if fanfare_present and line_present:
		return combatant
	var fighter := combatant.fighter.duplicate() as PresentationKit
	var victory := combatant.victory().duplicate() as FighterVictoryProfile
	if not fanfare_present:
		victory.fanfare = null
	if not line_present:
		victory.announcer_line = null
	fighter.victory = victory
	return CombatantPresentationKit.of(fighter, combatant.weapon, combatant.fighter_skin, combatant.weapon_skin)


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
	assert_true(profile.fanfare != null and profile.announcer_line != null, "fixture: Wolf's victory has a fanfare and a winner line")
	assert_eq(_count(director, profile.fanfare), 0, "fixture: nothing has played before the showcase runs")
	## 300 frames (5 s) runs well past the interactive time into the results.
	_run(director, 300)
	assert_false(director.is_cinematic(), "the showcase reached its results")
	assert_eq(_count(director, profile.fanfare), 0, "the showcase does not play the set horn")
	assert_eq(_count(director, profile.announcer_line), 1, "the winner line played exactly once")
	assert_eq(_count(director, combatant.fighter.character_call), 1, "the howl plays once under that line")
	assert_eq(director.fired_beats(), VictoryDirector.Beat.size(), "every beat fired")
	## The results screen can stay up indefinitely: nothing replays.
	_run(director, 600)
	assert_eq(_count(director, profile.fanfare), 0, "a long results screen never plays the horn")
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


func test_skipping_twice_or_pausing_replays_nothing() -> void:
	var director := _director(_combatant())
	var profile := director.profile()
	_run(director, 30)
	assert_true(director.is_cinematic(), "fixture: mid-cinematic")
	director.finish()
	director.finish()
	assert_eq(_count(director, profile.fanfare), 0, "a skip does not play the set horn")
	assert_eq(_count(director, profile.announcer_line), 1, "and the line once")
	assert_false(director.audio().is_tension_held(VictoryDirector.CHARGE_SLOT), "a skip never leaves the charge held")
	## A paused screen advances by zero; a resume continues where it was.
	for _i in 120:
		director.advance(0.0)
	_run(director, 120)
	assert_eq(_count(director, profile.fanfare), 0, "pause and resume do not play the horn")
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
	var director := _director(_combatant(false, false))
	var captions: Array[String] = []
	director.audio().caption_requested.connect(func(text: String, _seconds: float) -> void: captions.append(text))
	var cards := [0]
	director.card_requested.connect(func(_name: String, _title: String) -> void: cards[0] += 1)
	assert_true(director.profile().fanfare == null and director.profile().announcer_line == null, "fixture: both takes are missing")
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
	one_shots.append_array([victory.fanfare, victory.announcer_line])
	var checked := 0
	for stream in one_shots:
		if stream == null:
			continue
		checked += 1
		assert_false(bool(stream.get("loop")), "%s is a one-shot and must not loop" % stream.resource_path)
	assert_true(checked >= 6, "fixture: the announcer and victory takes are authored (%d checked)" % checked)
	var held := kits.weapon.stream_for(PresentationKit.CUE_CHARGE, 0)
	assert_true(held != null and bool(held.get("loop")), "the held charge loops — it has an owner that releases it")
