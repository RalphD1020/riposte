extends TestCase

## APP-E2E: the shipped main scene, end to end, through the real screens,
## buttons, input pipeline, clock, presenter, and teardown. Each case boots
## a fresh main.tscn with a scratch settings file and pinned seeds, drives
## frames through MatchScreen.advance_frame (the same path _process uses),
## and frees everything it built.
##
## See also: /docs/concepts/ux.md
## See also: /docs/reference/testing.md

const MAIN_SCENE := "res://src/main/main.tscn"
const SETTINGS_PATH := "user://riposte_e2e_settings.cfg"
const FRAME := 1.0 / 15.0
const MAX_FRAMES := 8000


func _init() -> void:
	suite_name = "APP-E2E"


class Booted:
	var main: RiposteMain
	var app: RiposteApp


func _boot() -> Booted:
	_remove_scratch()
	var scene := load(MAIN_SCENE) as PackedScene
	var booted := Booted.new()
	booted.main = scene.instantiate() as RiposteMain
	booted.main.settings_path = SETTINGS_PATH
	booted.main.seed_override = 7
	(Engine.get_main_loop() as SceneTree).root.add_child(booted.main)
	booted.app = booted.main.app()
	return booted


func _shutdown(booted: Booted) -> void:
	booted.main.queue_free()
	await await_frames(2)
	_remove_scratch()


func _remove_scratch() -> void:
	var absolute := ProjectSettings.globalize_path(SETTINGS_PATH)
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(absolute)


func _button(root: Node, text: String) -> Button:
	if root is Button and (root as Button).text == text:
		return root as Button
	for child in root.get_children():
		var found := _button(child, text)
		if found != null:
			return found
	return null


func _press(root: Node, text: String) -> bool:
	var target := _button(root, text)
	if target == null:
		return false
	target.pressed.emit()
	return true


func _match(booted: Booted) -> MatchScreen:
	var screen := booted.app.current_screen() as MatchScreen
	if screen != null:
		screen.set_process(false)
	return screen


## Built-in ui_* actions match keycode; project actions match physical keys.
func _key(key: Key, down: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	return event


func _push(event: InputEvent) -> void:
	(Engine.get_main_loop() as SceneTree).root.push_input(event, true)


func _run_until(screen: MatchScreen, done: Callable) -> int:
	var frames := 0
	while frames < MAX_FRAMES and not done.call():
		screen.advance_frame(FRAME)
		frames += 1
	return frames


func test_menu_quick_play_results_rematch_pause_quit() -> void:
	var booted := await _boot_ready()
	var app := booted.app
	assert_eq(app.router.current_id, AppScreen.Id.MAIN_MENU, "boots to the main menu")
	assert_eq(app.telemetry.count_product(ProductEvents.GAME_LOADED), 1, "load recorded once")
	assert_true(_press(app.current_screen(), "QUICK PLAY"), "Quick Play is on the menu")
	await await_frames(1)
	var first := _match(booted)
	assert_true(first != null, "Quick Play opens the duel")
	assert_eq(app.presentation_mount.get_child_count(), 1, "one presenter mounted")
	assert_eq(first.session.config.mode, MatchConfig.Mode.QUICK_PLAY_CPU, "against the CPU")
	var frames := _run_until(first, first.is_finished)
	assert_true(first.is_finished(), "an idle human still reaches a result (%d frames)" % frames)
	assert_eq(app.telemetry.count_product(ProductEvents.MATCH_FINISHED), 1, "finished exactly once")
	var first_session := first.session
	await await_frames(1)
	assert_false(is_instance_valid(first), "the finished duel screen was freed")
	assert_eq(app.router.current_id, AppScreen.Id.RESULTS, "results follow the match")
	var winner := first_session.state.match_winner
	var expected := "VICTORY" if winner == 0 else ("DEFEAT" if winner == 1 else "DRAW")
	var results := app.current_screen() as ResultsScreen
	assert_eq((results.lead.get_child(0) as Label).text, expected, "outcome from the human's side")
	assert_eq(app.presentation_mount.get_child_count(), 0, "leaving the duel disposed its presenter")
	assert_true(_press(results, "REMATCH"), "Rematch offered")
	await await_frames(1)
	var second := _match(booted)
	assert_true(second != null and second.session != first_session, "rematch composes a fresh session")
	assert_ne(second.session.config.seed_value, first_session.config.seed_value, "with a fresh seed")
	assert_eq(app.presentation_mount.get_child_count(), 1, "still exactly one presenter")
	_run_until(second, func() -> bool: return second.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	_push(_key(KEY_ESCAPE, true))
	_push(_key(KEY_ESCAPE, false))
	assert_true(second.is_paused() and second.pause_overlay.is_open(), "Escape pauses")
	var tick := second.session.state.tick
	for _i in 10:
		second.advance_frame(FRAME)
	assert_eq(second.session.state.tick, tick, "the clock is stopped while paused")
	assert_true(_press(second.pause_overlay, "QUIT TO MENU"), "Quit offered")
	await await_frames(2)
	assert_eq(app.router.current_id, AppScreen.Id.MAIN_MENU, "quit returns to the menu")
	assert_eq(app.telemetry.count_product(ProductEvents.MATCH_EXITED), 1, "exit recorded")
	assert_eq(app.presentation_mount.get_child_count(), 0, "no presenter outlives its match")
	await _shutdown(booted)


func test_pause_cancels_a_held_attack_and_resume_never_catches_up() -> void:
	var booted := await _boot_ready()
	booted.app.start_quick_play()
	await await_frames(1)
	var screen := _match(booted)
	_run_until(screen, func() -> bool: return screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	_push(_key(KEY_SPACE, true))
	assert_true(screen.human.input.is_attack_held(), "Space holds the attack")
	var me := screen.session.state.fighter(0)
	_run_until(screen, func() -> bool: return me.weapon.phase == CombatPhase.Id.CHARGING)
	assert_eq(me.weapon.phase, CombatPhase.Id.CHARGING, "holding past the tap threshold charges")
	screen.hud.pause_pressed.emit()
	assert_true(screen.is_paused(), "the HUD pause button pauses")
	assert_false(screen.human.input.is_attack_held(), "pausing drops the held attack")
	_push(_key(KEY_SPACE, false))
	assert_true(_press(screen.pause_overlay, "RESUME"), "Resume offered")
	await await_frames(1)
	assert_false(screen.is_paused(), "resumed")
	var tick := screen.session.state.tick
	screen.advance_frame(10.0)
	assert_true(screen.session.state.tick - tick <= FixedTickDriver.MAX_CATCH_UP_TICKS, "a long frame never fast-forwards")
	var swings := 0
	for event in screen.session.events:
		if event.type == DuelEventTypes.ATTACK_RELEASED and event.actor == 0:
			swings += 1
	assert_eq(swings, 0, "the canceled charge never swung")
	assert_ne(me.weapon.phase, CombatPhase.Id.CHARGING, "and did not survive the pause")
	await _shutdown(booted)


func test_training_is_reached_from_how_to_play_and_coaches_by_doing() -> void:
	var booted := await _boot_ready()
	var app := booted.app
	assert_true(_press(app.current_screen(), "HOW TO PLAY"), "How to Play on the menu")
	await await_frames(1)
	assert_eq(app.router.current_id, AppScreen.Id.HOW_TO_PLAY, "How to Play opens")
	assert_true(_press(app.current_screen(), "START TRAINING"), "training offered")
	await await_frames(1)
	var screen := _match(booted)
	assert_eq(screen.session.config.mode, MatchConfig.Mode.TRAINING, "training mode")
	assert_eq(screen.hud.prompt_title(), "MOVE", "first lesson: move")
	_run_until(screen, func() -> bool: return screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	Input.action_press(InputActions.MOVE_RIGHT)
	_run_until(screen, func() -> bool: return screen.tutorial.step != TutorialTracker.Step.MOVE)
	Input.action_release(InputActions.MOVE_RIGHT)
	assert_eq(screen.hud.prompt_title(), "QUICK CUT", "moving completes the first lesson")
	_push(_key(KEY_SPACE, true))
	_push(_key(KEY_SPACE, false))
	_run_until(screen, func() -> bool: return screen.tutorial.step != TutorialTracker.Step.QUICK_CUT)
	assert_eq(screen.hud.prompt_title(), "CHARGE", "a tap teaches the quick cut")
	await _shutdown(booted)


func test_settings_drill_down_saves_and_escape_walks_back() -> void:
	var booted := await _boot_ready()
	var app := booted.app
	assert_true(_press(app.current_screen(), "SETTINGS"), "Settings on the menu")
	await await_frames(1)
	var screen := app.current_screen() as SettingsScreen
	assert_true(screen != null, "Settings opens")
	assert_true(_press(screen, "Display"), "Display section listed")
	await await_frames(1)
	var toggle := _find_toggle(screen, "Reduced motion")
	assert_true(toggle != null and not toggle.button_pressed, "Reduced motion starts off")
	toggle.button_pressed = true
	var reloaded := PlayerSettings.new()
	reloaded.load_from(SETTINGS_PATH)
	assert_true(reloaded.reduced_motion, "the toggle persisted immediately")
	assert_true(app.presentation_options().reduced_motion, "and reaches the presentation")
	_push(_key(KEY_ESCAPE, true))
	await await_frames(1)
	assert_eq(screen.panel.section(), SettingsPanel.LIST, "Escape leaves the section first")
	_push(_key(KEY_ESCAPE, true))
	await await_frames(1)
	assert_eq(app.router.current_id, AppScreen.Id.MAIN_MENU, "then leaves Settings")
	await _shutdown(booted)


func test_touch_moves_and_attacks_through_the_same_input_path() -> void:
	var booted := await _boot_ready()
	var screen := await _active_duel(booted)
	var touch := screen.touch
	var me := screen.session.state.fighter(0)
	var start_x := me.x
	var start_y := me.y
	var forward_x := me.duel_forward_x
	var forward_y := me.duel_forward_y
	var stick := touch.move_zone().get_center()
	assert_true(touch.handle(_finger(0, stick, true)), "a thumb in the move zone claims the stick")
	## Footwork is duel-relative (MOVE-001), so a thumb pushed away from the
	## player closes the measure rather than walking a compass direction.
	touch.handle(_slide(0, stick - Vector2(0.0, TouchControls.JOYSTICK_RADIUS)))
	for _i in 6:
		screen.advance_frame(FRAME)
	var advance := (me.x - start_x) * forward_x + (me.y - start_y) * forward_y
	assert_true(advance > 0.05, "pushing the stick forward walks toward the opponent (%.3f m)" % advance)
	touch.handle(_finger(0, stick, false))
	var zone := touch.attack_zone().get_center()
	touch.handle(_finger(1, zone, true))
	assert_true(screen.human.input.is_attack_held(), "the attack zone holds the attack")
	touch.handle(_finger(1, zone, false))
	screen.advance_frame(FRAME)
	assert_eq(_swings(screen), 1, "lifting the finger swings once")
	touch.handle(_finger(2, zone, true))
	touch.handle(_finger(2, zone, false, true))
	screen.advance_frame(FRAME)
	assert_false(screen.human.input.is_attack_held(), "an OS-canceled touch drops the attack")
	assert_eq(_swings(screen), 1, "and never swings")
	await _shutdown(booted)


## Sequentially is not the same as simultaneously: a right thumb that steals
## the stick, or a left thumb that drops the hold, only shows up when both are
## down at once. Independent `index` values are the whole mechanism.
func test_both_thumbs_work_at_the_same_time() -> void:
	var booted := await _boot_ready()
	var screen := await _active_duel(booted)
	var touch := screen.touch
	var me := screen.session.state.fighter(0)
	var stick := touch.move_zone().get_center()
	var forward_x := me.duel_forward_x
	var forward_y := me.duel_forward_y
	var start_x := me.x
	var start_y := me.y
	touch.handle(_finger(0, stick, true))
	touch.handle(_slide(0, stick - Vector2(0.0, TouchControls.JOYSTICK_RADIUS)))
	touch.handle(_finger(1, touch.attack_zone().get_center(), true))
	assert_true(screen.human.input.is_attack_held(), "the right thumb holds while the left thumb steers")
	for _i in 8:
		screen.advance_frame(FRAME)
	assert_true(screen.human.input.is_attack_held(), "and keeps holding across frames of movement")
	var advance := (me.x - start_x) * forward_x + (me.y - start_y) * forward_y
	assert_true(advance > 0.05, "while the fighter really walked forward (%.3f m)" % advance)
	assert_true(me.weapon.charge > 0.0, "and the wind-back earned charge at the same time")
	touch.handle(_finger(1, touch.attack_zone().get_center(), false))
	screen.advance_frame(FRAME)
	assert_eq(_swings(screen), 1, "releasing the right thumb swings once")
	assert_true(touch.handle(_slide(0, stick)), "and the left thumb still owns its stick")
	await _shutdown(booted)


## MOVE-002 through a thumb. The gesture is "the same direction twice" in duel
## axes, so this taps the sector and comes to rest, never a screen point.
func test_a_thumb_double_tap_bursts_in_the_duel_direction() -> void:
	var booted := await _boot_ready()
	var screen := await _active_duel(booted)
	var touch := screen.touch
	var stick := touch.move_zone().get_center()
	var reach := TouchControls.JOYSTICK_RADIUS
	var offsets := {
		MovementGestureState.BurstKind.FORWARD_DASH: Vector2(0.0, -reach),
		MovementGestureState.BurstKind.BACK_DASH: Vector2(0.0, reach),
		MovementGestureState.BurstKind.RIGHT_STEP: Vector2(reach, 0.0),
		MovementGestureState.BurstKind.LEFT_STEP: Vector2(-reach, 0.0),
	}
	for kind: MovementGestureState.BurstKind in offsets.keys():
		var before := _bursts(screen)
		for _tap in 2:
			touch.handle(_finger(0, stick, true))
			touch.handle(_slide(0, stick + (offsets[kind] as Vector2)))
			screen.advance_frame(FRAME)
			## Lifting the thumb *is* coming to rest; the recognizer requires
			## it between taps, so a held push can never dash.
			touch.handle(_finger(0, stick, false))
			screen.advance_frame(FRAME)
		var launched := _bursts(screen)
		assert_eq(launched.size(), before.size() + 1, "one burst per double tap, not two")
		assert_eq(launched[launched.size() - 1], kind, "and it is the direction the thumb pushed")
	await _shutdown(booted)


func test_losing_focus_pauses_without_attacking() -> void:
	var booted := await _boot_ready()
	var screen := await _active_duel(booted)
	_push(_key(KEY_SPACE, true))
	assert_true(screen.human.input.is_attack_held(), "fixture: Space is held")
	screen.notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	assert_true(screen.is_paused() and screen.pause_overlay.is_open(), "focus loss pauses the duel")
	assert_false(screen.human.input.is_attack_held(), "and drops the held attack")
	_push(_key(KEY_SPACE, false))
	for _i in 4:
		screen.advance_frame(FRAME)
	assert_eq(_swings(screen), 0, "releasing Space after the pause attacks nobody")
	await _shutdown(booted)


func test_pause_sheet_pages_walk_back_with_escape_and_save_volume_on_close() -> void:
	var booted := await _boot_ready()
	var screen := await _active_duel(booted)
	screen.pause()
	var overlay := screen.pause_overlay
	assert_true(_press(overlay, "SETTINGS"), "Settings offered while paused")
	await await_frames(1)
	assert_eq(overlay.page(), PauseOverlay.Page.SETTINGS, "Settings opens inside the pause sheet")
	assert_true(_press(overlay, "Audio"), "Audio section listed")
	await await_frames(1)
	var panel := overlay.find_child("SettingsPanel", true, false) as SettingsPanel
	var slider := _find_slider(panel, "Master volume")
	assert_true(slider != null, "master volume slider shown")
	slider.value = 0.25
	var master := AudioServer.get_bus_index(AudioBuses.MASTER)
	assert_near(AudioServer.get_bus_volume_db(master), linear_to_db(0.25), 0.01, "dragging applies live")
	_push(_key(KEY_ESCAPE, true))
	assert_eq(panel.section(), SettingsPanel.LIST, "Escape leaves the section first")
	_push(_key(KEY_ESCAPE, true))
	assert_eq(overlay.page(), PauseOverlay.Page.MENU, "then returns to the pause menu")
	var reloaded := PlayerSettings.new()
	reloaded.load_from(SETTINGS_PATH)
	assert_near(reloaded.master_volume, 0.25, 1e-6, "closing the panel saved the drag once")
	assert_true(_press(overlay, "HOW TO PLAY"), "How to Play offered while paused")
	await await_frames(1)
	assert_eq(overlay.page(), PauseOverlay.Page.HOW_TO_PLAY, "How to Play opens inside the pause sheet")
	_push(_key(KEY_ESCAPE, true))
	assert_eq(overlay.page(), PauseOverlay.Page.MENU, "Escape returns to the pause menu")
	_push(_key(KEY_ESCAPE, true))
	await await_frames(1)
	assert_false(screen.is_paused(), "Escape on the pause menu resumes")
	booted.app.settings.master_volume = 1.0
	booted.app.settings.apply_audio()
	await _shutdown(booted)


func test_f3_toggles_combat_diagnostics_in_debug_builds() -> void:
	assert_true(OS.is_debug_build(), "fixture: the harness runs a debug build")
	var booted := await _boot_ready()
	var screen := await _active_duel(booted)
	assert_false(screen.debug_overlay.visible, "diagnostics hidden by default")
	_push(_key(KEY_F3, true))
	assert_true(screen.debug_overlay.visible, "F3 shows them")
	screen.advance_frame(FRAME)
	var text := screen.debug_overlay.text()
	assert_true(text.contains("distance"), "with live spacing numbers")
	## The physical profile has to be there too: a derived inertia that
	## disagrees with the authored mass is the single most common cause of a
	## fighter feeling wrong, and it is invisible without this.
	assert_true(text.contains("body") and text.contains("kg"), "and the fighter's physical profile")
	assert_true(text.contains("blade") and text.contains("tip"), "and the weapon's")
	_push(_key(KEY_F3, true))
	assert_false(screen.debug_overlay.visible, "F3 hides them again")
	await _shutdown(booted)


func test_results_without_a_match_fall_back_to_the_menu() -> void:
	var booted := await _boot_ready()
	var app := booted.app
	assert_true(app.last_session == null, "fixture: no match has been played")
	app.go_to(AppScreen.Id.RESULTS)
	await await_frames(2)
	assert_eq(app.router.current_id, AppScreen.Id.MAIN_MENU, "an empty results screen hands back to the menu")
	await _shutdown(booted)


func _boot_ready() -> Booted:
	var booted := _boot()
	await await_frames(1)
	return booted


## Quick Play, stepped to the first fighting tick.
func _active_duel(booted: Booted) -> MatchScreen:
	booted.app.start_quick_play()
	await await_frames(1)
	var screen := _match(booted)
	_run_until(screen, func() -> bool: return screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	assert_eq(screen.session.state.phase, MatchPhase.Id.ROUND_ACTIVE, "fixture: the round is live")
	return screen


func _swings(screen: MatchScreen) -> int:
	var count := 0
	for event in screen.session.events:
		if event.type == DuelEventTypes.ATTACK_RELEASED and event.actor == 0:
			count += 1
	return count


func _bursts(screen: MatchScreen) -> Array[MovementGestureState.BurstKind]:
	var kinds: Array[MovementGestureState.BurstKind] = []
	for event in screen.session.events:
		if event.type == DuelEventTypes.BURST_STARTED and event.actor == 0:
			kinds.append(int(event.number(DuelEventKeys.BURST)) as MovementGestureState.BurstKind)
	return kinds


func _finger(index: int, at: Vector2, down: bool, canceled: bool = false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	event.canceled = canceled
	return event


func _slide(index: int, at: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	return event


func _find_slider(root: Node, accessible_name: String) -> HSlider:
	if root is HSlider and (root as HSlider).accessibility_name == accessible_name:
		return root as HSlider
	for child in root.get_children():
		var found := _find_slider(child, accessible_name)
		if found != null:
			return found
	return null


func _find_toggle(root: Node, text: String) -> CheckButton:
	if root is CheckButton and (root as CheckButton).text == text:
		return root as CheckButton
	for child in root.get_children():
		var found := _find_toggle(child, text)
		if found != null:
			return found
	return null
