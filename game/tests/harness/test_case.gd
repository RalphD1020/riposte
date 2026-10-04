class_name TestCase
extends RefCounted

## Assertion base for headless behavioral proofs (TEST-TRUTH-001).
##
## Cases are methods named `test_*`, run in declaration order. Every case must
## record at least one assertion; a zero-assertion case fails its suite. Cases
## may be coroutines. Expected values must come from the test, never from the
## production code under test.
##
## Implements: /spec/invariants.md#test-truth-001
## See also: /docs/reference/testing.md

const CASE_PREFIX := "test_"

var suite_name: String = ""
var failures: PackedStringArray = PackedStringArray()
var assertion_count: int = 0
var case_count: int = 0
var _current_case: String = ""


func run() -> void:
	for method in case_names():
		_current_case = method
		var before := assertion_count
		await call(method)
		case_count += 1
		if assertion_count == before:
			failures.append("%s recorded zero assertions" % method)
	_current_case = ""


func case_names() -> PackedStringArray:
	var names := PackedStringArray()
	var script := get_script() as GDScript
	if script == null:
		return names
	for method: Dictionary in script.get_script_method_list():
		var method_name := str(method["name"])
		if method_name.begins_with(CASE_PREFIX) and not names.has(method_name):
			names.append(method_name)
	return names


func assert_true(condition: bool, message: String) -> void:
	assertion_count += 1
	if not condition:
		_fail(message)


func assert_false(condition: bool, message: String) -> void:
	assertion_count += 1
	if condition:
		_fail(message)


func assert_eq(actual: Variant, expected: Variant, message: String) -> void:
	assertion_count += 1
	if not values_equal(actual, expected):
		_fail("%s (got %s, expected %s)" % [message, str(actual), str(expected)])


func assert_ne(actual: Variant, unexpected: Variant, message: String) -> void:
	assertion_count += 1
	if values_equal(actual, unexpected):
		_fail("%s (both %s)" % [message, str(actual)])


func assert_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	assertion_count += 1
	if not (absf(actual - expected) <= tolerance):
		_fail("%s (got %s, expected %s ± %s)" % [message, str(actual), str(expected), str(tolerance)])


func assert_between(actual: float, low: float, high: float, message: String) -> void:
	assertion_count += 1
	if not (actual >= low and actual <= high):
		_fail("%s (got %s, expected [%s, %s])" % [message, str(actual), str(low), str(high)])


func assert_finite(actual: float, message: String) -> void:
	assertion_count += 1
	if not is_finite(actual):
		_fail("%s (got %s)" % [message, str(actual)])


## Type-aware equality. Numbers compare numerically and String/StringName
## compare by text; any other cross-type comparison is unequal.
static func values_equal(actual: Variant, expected: Variant) -> bool:
	var actual_type := typeof(actual)
	var expected_type := typeof(expected)
	if actual_type == expected_type:
		return actual == expected
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if numbers.has(actual_type) and numbers.has(expected_type):
		return float(actual) == float(expected)
	var texts := [TYPE_STRING, TYPE_STRING_NAME]
	if texts.has(actual_type) and texts.has(expected_type):
		return str(actual) == str(expected)
	return false


func await_frames(count: int) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for _i in count:
		await tree.process_frame


func _fail(message: String) -> void:
	if _current_case == "":
		failures.append(message)
	else:
		failures.append("%s: %s" % [_current_case, message])
