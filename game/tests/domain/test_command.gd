extends TestCase

## CMD: PlayerCommand quantizes, clamps untrusted input, and round-trips.
##
## Implements: /spec/invariants.md#cmd-001
## See also: /docs/concepts/simulation.md


func _init() -> void:
	suite_name = "CMD"


func test_diagonal_input_is_clamped_to_unit_length() -> void:
	var command := PlayerCommand.create(5, 1.0, 1.0)
	assert_eq(command.tick, 5, "tick kept")
	assert_eq(command.move_x, 707, "x normalized")
	assert_eq(command.move_y, 707, "y normalized")
	assert_true(SimMath.length(command.axis_x(), command.axis_y()) <= 1.0, "magnitude at most 1")


func test_partial_input_is_preserved() -> void:
	var command := PlayerCommand.create(0, 0.25, -0.5)
	assert_eq(command.move_x, 250, "analog x kept")
	assert_eq(command.move_y, -500, "analog y kept")


func test_non_finite_input_becomes_neutral() -> void:
	var command := PlayerCommand.create(1, NAN, INF)
	assert_eq(command.move_x, 0, "NaN x neutral")
	assert_eq(command.move_y, 0, "Inf y neutral")


func test_sanitized_clamps_untrusted_fields() -> void:
	var hostile := PlayerCommand.new()
	hostile.move_x = 99999
	hostile.move_y = -99999
	var clean := hostile.sanitized()
	assert_eq(clean.move_x, PlayerCommand.AXIS_MAX, "x clamped")
	assert_eq(clean.move_y, -PlayerCommand.AXIS_MAX, "y clamped")


func test_pack_round_trip_preserves_every_field() -> void:
	var packed := PackedInt32Array()
	var original := PlayerCommand.create(42, -0.3, 0.6, true, true, true)
	original.append_to(packed)
	PlayerCommand.idle(43).append_to(packed)
	assert_eq(packed.size(), 2 * PlayerCommand.PACKED_STRIDE, "two commands packed")
	var restored := PlayerCommand.read_from(packed, 0)
	assert_eq(restored.tick, 42, "tick")
	assert_eq(restored.move_x, -300, "move x")
	assert_eq(restored.move_y, 600, "move y")
	assert_true(restored.attack_pressed and restored.attack_released and restored.attack_cancel, "all edges")
	assert_true(PlayerCommand.read_from(packed, 1).is_idle(), "idle command restored")


func test_out_of_range_read_is_idle() -> void:
	var packed := PackedInt32Array()
	assert_true(PlayerCommand.read_from(packed, 3).is_idle(), "missing command reads as idle")
	assert_eq(PlayerCommand.read_from(packed, -1).tick, 0, "negative index is idle")


func test_flags_encode_each_edge() -> void:
	assert_eq(PlayerCommand.create(0, 0.0, 0.0, true).flags(), PlayerCommand.FLAG_PRESSED, "press bit")
	assert_eq(PlayerCommand.create(0, 0.0, 0.0, false, true).flags(), PlayerCommand.FLAG_RELEASED, "release bit")
	assert_eq(PlayerCommand.create(0, 0.0, 0.0, false, false, true).flags(), PlayerCommand.FLAG_CANCEL, "cancel bit")
	assert_false(PlayerCommand.create(0, 0.1, 0.0).is_idle(), "movement is not idle")
