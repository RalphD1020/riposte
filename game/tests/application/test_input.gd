extends TestCase

## INPUT: every device feeds one logical attack button and one move vector;
## cancellation never attacks (UX §28, §61–§63).
##
## See also: /docs/concepts/controls.md


func _init() -> void:
	suite_name = "INPUT"


func test_any_source_holds_the_one_button() -> void:
	var input := HumanInputState.new()
	input.attack_down(HumanInputState.SOURCE_POINTER)
	assert_true(input.consume(0).attack_pressed, "first source presses")
	input.attack_down(HumanInputState.SOURCE_KEY)
	assert_false(input.consume(1).attack_pressed, "second source is not a new press")
	input.attack_up(HumanInputState.SOURCE_POINTER)
	assert_false(input.consume(2).attack_released, "still held by the key")
	input.attack_up(HumanInputState.SOURCE_KEY)
	assert_true(input.consume(3).attack_released, "released when the last source lets go")


## COMBAT-READABILITY-001: toggle charge is an input accessibility choice, not
## a rule. Tap to begin and tap to swing produces exactly the press and release
## edges a hold produces, tick for tick, so the simulation cannot tell them
## apart; and no hold is ever needed.
func test_toggle_charge_emits_the_same_commands_as_holding() -> void:
	var held := HumanInputState.new()
	var toggled := HumanInputState.new()
	toggled.toggle_charge = true
	assert_false(held.toggle_charge, "fixture: holding is the default")
	var hold_stream: Array[PlayerCommand] = []
	var toggle_stream: Array[PlayerCommand] = []
	for tick in 12:
		if tick == 2:
			held.attack_down(HumanInputState.SOURCE_KEY)
			toggled.attack_down(HumanInputState.SOURCE_KEY)
			toggled.attack_up(HumanInputState.SOURCE_KEY)
		if tick == 8:
			held.attack_up(HumanInputState.SOURCE_KEY)
			toggled.attack_down(HumanInputState.SOURCE_TOUCH)
			toggled.attack_up(HumanInputState.SOURCE_TOUCH)
		if tick > 2 and tick < 8:
			assert_true(toggled.is_attack_held(), "tick %d: the toggled charge holds with nothing pressed" % tick)
		hold_stream.append(held.consume(tick))
		toggle_stream.append(toggled.consume(tick))
	for tick in 12:
		var h := hold_stream[tick]
		var t := toggle_stream[tick]
		assert_eq([t.attack_pressed, t.attack_released, t.attack_cancel], [h.attack_pressed, h.attack_released, h.attack_cancel], "tick %d: the same command edges" % tick)
	assert_false(toggled.is_attack_held(), "the second tap released the charge")


func test_edges_are_consumed_once_and_sub_frame_taps_survive() -> void:
	var input := HumanInputState.new()
	input.attack_down(HumanInputState.SOURCE_TOUCH)
	input.attack_up(HumanInputState.SOURCE_TOUCH)
	var tap := input.consume(0)
	assert_true(tap.attack_pressed and tap.attack_released, "a tap shorter than a tick still arrives")
	assert_true(input.consume(1).is_idle(), "edges do not repeat")
	input.attack_up(HumanInputState.SOURCE_TOUCH)
	assert_true(input.consume(2).is_idle(), "stray release ignored")


func test_cancel_never_attacks() -> void:
	var input := HumanInputState.new()
	input.set_key_axis(1.0, 0.0)
	input.attack_down(HumanInputState.SOURCE_POINTER)
	input.consume(0)
	input.cancel_all()
	var command := input.consume(1)
	assert_true(command.attack_cancel, "cancel reported")
	assert_false(command.attack_released, "no release that would swing")
	assert_eq(command.move_x, 0, "movement returns to neutral")
	assert_false(input.is_attack_held(), "nothing held")
	input.cancel_all()
	assert_false(input.consume(2).attack_cancel, "cancel with nothing held is silent")


func test_touch_overrides_keys_while_a_thumb_is_down() -> void:
	var input := HumanInputState.new()
	input.set_key_axis(1.0, 0.0)
	input.set_touch_axis(0.0, 1.0, true)
	var touched := input.consume(0)
	assert_eq(touched.move_x, 0, "touch x")
	assert_eq(touched.move_y, PlayerCommand.AXIS_MAX, "touch y")
	input.set_touch_axis(0.0, 1.0, false)
	assert_eq(input.consume(1).move_x, PlayerCommand.AXIS_MAX, "keys again once the thumb lifts")


## Two thumbs at once is the normal mobile posture, not an edge case: one
## steers while the other attacks. Both have to survive the same tick, or
## every attack on a phone would cancel the footwork that set it up.
func test_a_second_finger_attacking_preserves_both_inputs() -> void:
	var input := HumanInputState.new()
	input.set_touch_axis(0.0, 1.0, true)
	input.attack_down(HumanInputState.SOURCE_TOUCH)
	var both := input.consume(0)
	assert_eq(both.move_y, PlayerCommand.AXIS_MAX, "the steering thumb is still steering")
	assert_true(both.attack_pressed, "while the other thumb presses")
	## And the reverse order, because a player does not coordinate their
	## thumbs to the tick.
	var reversed := HumanInputState.new()
	reversed.attack_down(HumanInputState.SOURCE_TOUCH)
	reversed.set_touch_axis(-1.0, 0.0, true)
	var swapped := reversed.consume(0)
	assert_eq(swapped.move_x, -PlayerCommand.AXIS_MAX, "steering arrives after the press just as well")
	assert_true(swapped.attack_pressed, "and the press is still owed")
	## Lifting the steering thumb must not release the attack: they are
	## different fingers reporting through the same source name.
	reversed.set_touch_axis(0.0, 0.0, false)
	var lifted := reversed.consume(1)
	assert_eq(lifted.move_x, 0, "steering stops")
	assert_false(lifted.attack_released, "but the attack is still held")
	assert_true(reversed.is_attack_held(), "by the finger that pressed it")


func test_the_pad_uses_the_same_attack_and_a_disconnect_cancels_it() -> void:
	var input := HumanInputState.new()
	input.attack_down(HumanInputState.SOURCE_PAD)
	var held := input.consume(0)
	assert_true(held.attack_pressed, "the face button is the one attack")
	assert_true(input.is_attack_held(), "and it stays held")
	var screen := MatchScreen.new()
	screen.human = HumanController.new()
	screen.human.input.attack_down(HumanInputState.SOURCE_PAD)
	screen.release_pad()
	var canceled := screen.human.input.consume(1)
	assert_true(canceled.attack_cancel, "unplugging the pad cancels the hold")
	assert_false(canceled.attack_pressed, "and does not start a new press")
	screen.free()
	var map := FileAccess.get_file_as_string("res://project.godot")
	assert_true(map.contains("InputEventJoypadMotion"), "the stick is on the move actions")
	assert_true(map.contains("InputEventJoypadButton"), "the face button and start are actions")


func test_human_controller_reads_its_input() -> void:
	var controller := HumanController.new()
	var state := DuelFixture.state(DuelFixture.rules())
	controller.input.attack_down(HumanInputState.SOURCE_KEY)
	var command := controller.command_for(state, 0)
	assert_true(command.attack_pressed, "device input becomes the command")
	assert_eq(command.tick, state.tick, "stamped with the state tick")
