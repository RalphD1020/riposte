extends TestCase

## HARNESS: proves the assertion base enforces TEST-TRUTH-001 mechanics.
##
## Implements: /spec/invariants.md#test-truth-001
## See also: /docs/reference/testing.md


class _EmptyCaseSuite:
	extends TestCase

	func test_does_nothing() -> void:
		pass


class _FailingCaseSuite:
	extends TestCase

	func test_reports_mismatch() -> void:
		assert_eq(2, 3, "two is not three")


class _NanCaseSuite:
	extends TestCase

	func test_nan_is_not_near() -> void:
		assert_near(NAN, 0.0, 1.0, "nan never satisfies a tolerance")


func _init() -> void:
	suite_name = "HARNESS"


func test_numbers_compare_numerically() -> void:
	assert_true(TestCase.values_equal(1, 1.0), "int 1 equals float 1.0")
	assert_false(TestCase.values_equal(1, 2), "1 differs from 2")


func test_text_compares_across_string_kinds() -> void:
	assert_true(TestCase.values_equal("duel", &"duel"), "String equals StringName with same text")
	assert_false(TestCase.values_equal("1", 1), "text never equals a number")


func test_zero_assertion_case_fails_suite() -> void:
	var probe := _EmptyCaseSuite.new()
	assert_eq(probe.failures.size(), 0, "probe starts clean")
	await probe.run()
	assert_eq(probe.case_count, 1, "probe ran its single case")
	assert_eq(probe.failures.size(), 1, "zero-assertion case recorded one failure")
	assert_true(probe.failures[0].contains("zero assertions"), "failure names the zero-assertion rule")


func test_failed_assertion_names_its_case() -> void:
	var probe := _FailingCaseSuite.new()
	await probe.run()
	assert_eq(probe.assertion_count, 1, "probe counted its assertion")
	assert_eq(probe.failures.size(), 1, "mismatch recorded one failure")
	assert_true(probe.failures[0].begins_with("test_reports_mismatch:"), "failure is prefixed with the case name")


func test_nan_never_passes_near() -> void:
	var probe := _NanCaseSuite.new()
	await probe.run()
	assert_eq(probe.failures.size(), 1, "NaN fails assert_near")
