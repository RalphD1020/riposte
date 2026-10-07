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


func test_human_controller_reads_its_input() -> void:
	var controller := HumanController.new()
	var state := DuelFixture.state(DuelFixture.rules())
	controller.input.attack_down(HumanInputState.SOURCE_KEY)
	var command := controller.command_for(state, 0)
	assert_true(command.attack_pressed, "device input becomes the command")
	assert_eq(command.tick, state.tick, "stamped with the state tick")
