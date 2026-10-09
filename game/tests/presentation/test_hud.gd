extends TestCase

## PRES-HUD: the HUD shows exactly what the snapshot says, from the human's
## side; touch controls turn fingers into move/attack intents.
##
## Implements: /spec/invariants.md#ux-001
## See also: /docs/concepts/ux.md
## See also: /docs/concepts/controls.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "PRES-HUD"
	_rules = StandardDuelRules.create()


func _state() -> MatchState:
	return DuelSetup.new_state(_rules, 3)


func _project(state: MatchState) -> PresentationSnapshot:
	return SnapshotProjector.project(state, _rules)


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func test_banner_walks_round_ready_duel_then_names_the_outcome() -> void:
	var state := _state()
	var third := floori(float(_rules.intro_ticks) / 3.0)
	assert_true(third >= 1, "fixture: intro long enough for three beats")
	state.set_phase(MatchPhase.Id.ROUND_INTRO)
	assert_eq(HudCopy.banner(_project(state), 0), "ROUND 1", "first beat names the round")
	state.phase_ticks = third
	assert_eq(HudCopy.banner(_project(state), 0), "READY", "second beat")
	state.phase_ticks = 2 * third
	assert_eq(HudCopy.banner(_project(state), 0), "DUEL", "third beat")
	state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
	assert_eq(HudCopy.banner(_project(state), 0), "", "no banner while fighting")
	state.set_phase(MatchPhase.Id.ROUND_RESULT)
	state.round_winner = 0
	assert_eq(HudCopy.banner(_project(state), 0), "ROUND WON", "slot 0 human won")
	assert_eq(HudCopy.banner(_project(state), 1), "ROUND LOST", "same round from slot 1")
	state.round_winner = MatchPhase.DRAW
	assert_eq(HudCopy.banner(_project(state), 0), "ROUND DRAWN", "double kill")
	state.round_winner = 1
	state.end_reason = MatchPhase.REASON_TIMEOUT
	assert_eq(HudCopy.banner(_project(state), 1), "TIME · ROUND WON", "timeouts say so")
	## Winning a round you also died in needs explaining, or it reads as a bug.
	state.end_reason = MatchPhase.REASON_TRADE_FIRST_CONTACT
	assert_eq(HudCopy.banner(_project(state), 1), "TRADE · ROUND WON", "and so does a trade won on arrival order")
	state.end_reason = MatchPhase.REASON_KILL
	assert_eq(HudCopy.banner(_project(state), 1), "ROUND WON", "an ordinary kill needs no explanation")
	state.set_phase(MatchPhase.Id.MATCH_ENDED)
	state.match_winner = 1
	assert_eq(HudCopy.banner(_project(state), 0), "DEFEAT", "match outcome from the human's side")


func test_hud_shows_health_pips_round_and_low_time_from_the_humans_side() -> void:
	var hud := DuelHud.create("YOU", "CPU · Medium", 1, DuelSide.Id.LIGHT_SOUTH)
	_root().add_child(hud)
	var state := _state()
	state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
	state.round_number = 2
	state.scores = PackedInt32Array([2, 1])
	state.fighter(1).health = 40.0
	state.fighter(0).health = 75.0
	state.round_ticks = _rules.round_time_limit_ticks - 300
	hud.update(_project(state))
	assert_eq(hud.health_bar(0).value, 40.0, "left bar is the human (slot 1)")
	assert_eq(hud.health_bar(0).accessibility_description, "40 of 100", "health announced as text")
	assert_eq(hud.health_bar(1).value, 75.0, "right bar is the opponent")
	assert_eq(hud.pips(0).wins, 1, "human pips")
	assert_eq(hud.pips(1).wins, 2, "opponent pips")
	assert_eq(hud.pips(0).accessibility_name, "YOU rounds won: 1 of 3", "pips announced as text")
	assert_eq(hud.clock_text(), "0:05", "low-time clock appears in the last ten seconds")
	state.round_ticks = 0
	hud.update(_project(state))
	assert_eq(hud.clock_text(), "", "no clock with time to spare")
	assert_eq(hud.banner_text(), "", "no banner mid-round")
	hud.queue_free()


func test_hud_shows_stamina_bar_and_condition() -> void:
	var hud := DuelHud.create("YOU", "CPU · Medium", 0, DuelSide.Id.LIGHT_SOUTH)
	_root().add_child(hud)
	var state := _state()
	state.set_phase(MatchPhase.Id.ROUND_ACTIVE)
	hud.update(_project(state))
	assert_eq(hud.stamina_bar(0).value, _rules.fighter.base_stamina, "full stamina at start")
	assert_eq(hud.condition_label(0).text, "HEALTHY", "full health is HEALTHY")
	state.fighter(0).stamina = _rules.fighter.base_stamina * 0.5
	state.fighter(0).health = _rules.fighter.max_health * 0.2
	hud.update(_project(state))
	assert_true(hud.stamina_bar(0).value < _rules.fighter.base_stamina, "stamina bar drained")
	assert_eq(hud.condition_label(0).text, "CRITICAL", "20% health is CRITICAL")
	assert_true(hud.condition_icon(0).texture == HudIcons.condition(FighterCondition.Id.CRITICAL), "and the plate repeats it as a shape, not a colour")
	assert_ne(HudIcons.condition(FighterCondition.Id.CRITICAL).get_image().get_data(), HudIcons.condition(FighterCondition.Id.HEALTHY).get_image().get_data(), "each condition draws a different shape")
	hud.queue_free()


func test_intro_cards_borrow_the_banner_and_captions_time_out() -> void:
	var hud := DuelHud.create("YOU", "CPU · Medium", 0, DuelSide.Id.LIGHT_SOUTH)
	hud.reduced_motion = true
	_root().add_child(hud)
	var state := _state()
	hud.update(_project(state))
	var round_banner := hud.banner_text()
	assert_ne(round_banner, "", "precondition: the round intro has a banner")
	hud.show_card("WOLF")
	hud.update(_project(state))
	assert_eq(hud.banner_text(), "WOLF", "a card overrides the snapshot's banner")
	hud.show_card("")
	hud.update(_project(state))
	assert_eq(hud.banner_text(), round_banner, "and gives it back when the intro ends")
	hud.show_caption("Wold.", 0.5)
	assert_eq(hud.caption_text(), "Wold.", "captions show")
	hud._process(0.6)
	assert_eq(hud.caption_text(), "", "and clear on their own")
	hud.queue_free()


## Side must be legible as text, not only as a colour (SIDE-001): a player who
## cannot distinguish the two palettes still has to know which end is theirs.
func test_plates_name_the_side_as_well_as_the_fighter() -> void:
	var state := _state()
	var mine := state.fighter(1).side
	var hud := DuelHud.create(HudCopy.sided("YOU", mine), HudCopy.sided("CPU · Medium", DuelSide.other(mine)), 1, mine)
	_root().add_child(hud)
	hud.update(_project(state))
	var label := hud.pips(0).accessibility_name
	assert_true(label.contains("YOU"), "the plate still says who it is")
	assert_true(label.contains(DuelSide.label(mine)), "and which end they hold")
	assert_false(label.contains(DuelSide.label(DuelSide.other(mine))), "without naming the other one")
	hud.queue_free()


func test_prompt_shows_and_hides() -> void:
	var hud := DuelHud.create("YOU", "DUMMY", 0, DuelSide.Id.LIGHT_SOUTH)
	_root().add_child(hud)
	hud.show_prompt("QUICK CUT", "Tap attack")
	assert_eq(hud.prompt_title(), "QUICK CUT", "prompt visible")
	hud.hide_prompt()
	assert_eq(hud.prompt_title(), "", "prompt hidden")
	hud.queue_free()


func test_pause_button_is_touch_sized_named_and_never_takes_keyboard_focus() -> void:
	var hud := DuelHud.create("YOU", "CPU · Hard", 0, DuelSide.Id.LIGHT_SOUTH)
	_root().add_child(hud)
	var pause := hud.pause_button()
	var presses: Array[int] = []
	hud.pause_pressed.connect(func() -> void: presses.append(1))
	assert_true(pause.get_combined_minimum_size().x >= 48.0 and pause.get_combined_minimum_size().y >= 48.0, "48 px target")
	assert_eq(pause.accessibility_name, "Pause", "named for assistive tech")
	assert_eq(pause.focus_mode, Control.FOCUS_NONE, "Space attacks instead of pressing Pause")
	pause.pressed.emit()
	assert_eq(presses.size(), 1, "press emits pause_pressed")
	hud.queue_free()


class TouchRig:
	var controls: TouchControls
	var moves: Array[Vector2] = []
	var active: Array[bool] = []
	var pressed: int = 0
	var released: int = 0
	var canceled: int = 0

	func dispose() -> void:
		controls.queue_free()


func _touch_rig() -> TouchRig:
	var rig := TouchRig.new()
	rig.controls = TouchControls.new()
	_root().add_child(rig.controls)
	rig.controls.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	rig.controls.position = Vector2.ZERO
	rig.controls.size = Vector2(1000.0, 500.0)
	rig.controls.move_changed.connect(func(vector: Vector2, on: bool) -> void:
		rig.moves.append(vector)
		rig.active.append(on)
	)
	rig.controls.attack_pressed.connect(func() -> void: rig.pressed += 1)
	rig.controls.attack_released.connect(func() -> void: rig.released += 1)
	rig.controls.canceled.connect(func() -> void: rig.canceled += 1)
	return rig


func _touch(index: int, at: Vector2, down: bool, canceled: bool = false) -> InputEventScreenTouch:
	var event := InputEventScreenTouch.new()
	event.index = index
	event.position = at
	event.pressed = down
	event.canceled = canceled
	return event


func _drag(index: int, at: Vector2) -> InputEventScreenDrag:
	var event := InputEventScreenDrag.new()
	event.index = index
	event.position = at
	return event


func test_left_thumb_floats_a_joystick_in_arena_axes() -> void:
	var rig := _touch_rig()
	var radius := TouchControls.JOYSTICK_RADIUS
	assert_true(rig.controls.handle(_touch(0, Vector2(150.0, 400.0), true)), "a thumb in the lower-left claims the stick")
	assert_true(rig.controls.handle(_drag(0, Vector2(150.0 + radius, 400.0))), "drag handled")
	assert_true(rig.moves.back().is_equal_approx(Vector2(1.0, 0.0)), "screen right is arena +x")
	rig.controls.handle(_drag(0, Vector2(150.0, 400.0 - radius)))
	assert_true(rig.moves.back().is_equal_approx(Vector2(0.0, 1.0)), "screen up is arena +y")
	rig.controls.handle(_drag(0, Vector2(150.0 + 4.0 * radius, 400.0 - radius)))
	assert_near(rig.moves.back().length(), 1.0, 1e-6, "past the rim the base follows; full deflection")
	rig.controls.handle(_touch(0, Vector2(150.0, 400.0), false))
	assert_false(rig.active.back(), "lifting the thumb stops movement")
	assert_eq(rig.moves.back(), Vector2.ZERO, "and zeroes the vector")
	rig.dispose()


func test_attack_zone_presses_releases_and_cancels_without_attacking() -> void:
	var rig := _touch_rig()
	assert_true(rig.controls.handle(_touch(1, Vector2(850.0, 350.0), true)), "right side claims the attack")
	rig.controls.handle(_touch(1, Vector2(850.0, 350.0), false))
	assert_eq([rig.pressed, rig.released, rig.canceled], [1, 1, 0], "tap = press + release")
	rig.controls.handle(_touch(2, Vector2(850.0, 350.0), true))
	rig.controls.handle(_touch(2, Vector2(850.0, 350.0), false, true))
	assert_eq([rig.pressed, rig.released, rig.canceled], [2, 1, 1], "an OS-canceled touch cancels, never releases")
	rig.dispose()


func test_two_thumbs_never_steal_from_each_other() -> void:
	var rig := _touch_rig()
	rig.controls.handle(_touch(0, Vector2(150.0, 400.0), true))
	rig.controls.handle(_drag(0, Vector2(214.0, 400.0)))
	rig.controls.handle(_touch(1, Vector2(850.0, 400.0), true))
	rig.controls.handle(_touch(1, Vector2(850.0, 400.0), false))
	assert_true(rig.controls.is_moving(), "releasing the attack finger keeps moving")
	assert_true(rig.active.back(), "movement still active")
	assert_false(rig.controls.handle(_touch(3, Vector2(160.0, 420.0), true)), "a second left finger does not hijack the stick")
	rig.dispose()


func test_upper_screen_and_excluded_controls_belong_to_the_gui() -> void:
	var rig := _touch_rig()
	var button := Button.new()
	_root().add_child(button)
	button.position = Vector2(900.0, 420.0)
	button.size = Vector2(60.0, 60.0)
	rig.controls.exclusions.append(button)
	assert_false(rig.controls.handle(_touch(0, Vector2(850.0, 40.0), true)), "the top of the screen is not a control zone")
	assert_false(rig.controls.handle(_touch(1, Vector2(930.0, 450.0), true)), "a touch on the pause button is the button's")
	assert_eq(rig.pressed, 0, "neither attacked")
	button.queue_free()
	rig.dispose()


func test_reveal_and_disable_govern_visibility_and_forget_fingers() -> void:
	var rig := _touch_rig()
	assert_false(rig.controls.visible, "hidden until a touch device is known")
	rig.controls.reveal()
	assert_true(rig.controls.visible, "revealed")
	rig.controls.handle(_touch(0, Vector2(150.0, 400.0), true))
	rig.controls.set_enabled(false)
	assert_false(rig.controls.visible, "hidden while a modal owns the screen")
	assert_false(rig.controls.is_moving(), "fingers forgotten")
	assert_false(rig.active.back(), "movement stopped")
	rig.controls.set_enabled(true)
	assert_true(rig.controls.visible, "shown again on resume")
	rig.dispose()
