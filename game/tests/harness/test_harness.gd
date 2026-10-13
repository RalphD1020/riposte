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


## A benchmark only stops gating its own failed grades: a missed assertion is
## reported, but a benchmark's harness failure still fails the run, and an
## ordinary suite's failed assertion is never softened.
func test_a_benchmark_reports_missed_grades_but_never_hides_a_harness_failure() -> void:
	var ordinary := _FailingCaseSuite.new()
	await ordinary.run()
	assert_eq(ordinary.assertion_failure_count, 1, "fixture: one failed assertion")
	assert_eq(HeadlessRunner.verdict(ordinary), HeadlessRunner.Verdict.FAIL, "an ordinary failed assertion fails the run")
	var missed := _FailingCaseSuite.new()
	missed.benchmark_reason = "rules in transition"
	await missed.run()
	assert_eq(HeadlessRunner.verdict(missed), HeadlessRunner.Verdict.BENCHMARK_MISSED, "the same failure in a benchmark is reported, not gated")
	var vacuous := _EmptyCaseSuite.new()
	vacuous.benchmark_reason = "rules in transition"
	await vacuous.run()
	assert_eq(vacuous.assertion_failure_count, 0, "fixture: a zero-assertion case is a harness failure, not an assertion")
	assert_eq(HeadlessRunner.verdict(vacuous), HeadlessRunner.Verdict.FAIL, "a benchmark's harness failure still fails the run")
	var clean := _EmptyCaseSuite.new()
	assert_eq(HeadlessRunner.verdict(clean), HeadlessRunner.Verdict.PASS, "a suite with no failures passes")


## The gating run and the three audit runs partition the suites: every suite
## runs in exactly one process, and an unset tier is the gating one.
func test_tiers_partition_the_suites() -> void:
	var paths := HeadlessRunner.suite_paths()
	assert_true(paths.size() > 40, "fixture: the manifest registers the suites (%d)" % paths.size())
	for path in paths:
		var tiers := 0
		for tier: String in [HeadlessRunner.TIER_GATE, HeadlessRunner.TIER_BALANCE, HeadlessRunner.TIER_ACCEPT, HeadlessRunner.TIER_SHIP]:
			tiers += 1 if HeadlessRunner.in_tier(path, tier) else 0
		assert_eq(tiers, 1, "%s runs in exactly one process" % path)
		assert_eq(HeadlessRunner.in_tier(path, ""), HeadlessRunner.in_tier(path, HeadlessRunner.TIER_GATE), "%s: an unset tier is the gating tier" % path)
	assert_false(HeadlessRunner.in_tier("res://tests/application/test_cpu_balance.gd", HeadlessRunner.TIER_GATE), "CPU-BALANCE never runs in the gating tier")
	assert_true(HeadlessRunner.in_tier("res://tests/application/test_cpu_accept.gd", HeadlessRunner.TIER_ACCEPT), "CPU-ACCEPT runs only when asked for")
	assert_true(HeadlessRunner.in_tier("res://tests/domain/test_contact_ship.gd", HeadlessRunner.TIER_SHIP), "the contact corpora run only when asked for")
	assert_true(HeadlessRunner.in_tier("res://tests/domain/test_contact_integrity.gd", HeadlessRunner.TIER_GATE), "the contact witnesses stay in the gate")


## TEST-TIER-001: the manifest is the truth the selectors act on. Each entry is
## a real suite under its own name with a size and a budget; every area names
## only registered suites; and every production script has an owning area, so
## `test:changed` can never silently select nothing for a real change.
func test_the_suite_manifest_is_complete_and_truthful() -> void:
	var manifest := HeadlessRunner.manifest()
	var names := PackedStringArray()
	for entry: Dictionary in manifest["suites"]:
		var script := load(String(entry["path"])) as GDScript
		assert_true(script != null and script.can_instantiate(), "%s loads" % entry["path"])
		if script == null:
			continue
		var suite := script.new() as TestCase
		assert_eq(suite.suite_name, String(entry["name"]), "%s is registered under its own name" % entry["path"])
		assert_true(["fast", "focused", "gate", "balance", "accept", "ship"].has(String(entry["tier"])), "%s has a known size (%s)" % [entry["name"], entry["tier"]])
		assert_true(int(entry["budget_ms"]) > 0, "%s has a budget" % entry["name"])
		names.append(String(entry["name"]))
	var prefixes := PackedStringArray()
	for area: String in manifest["areas"]:
		for name: String in manifest["areas"][area]["suites"]:
			assert_true(names.has(name), "area %s names a registered suite (%s)" % [area, name])
		for prefix: String in manifest["areas"][area]["paths"]:
			prefixes.append(prefix)
	var unowned := PackedStringArray()
	for script_path in _scripts_under("res://src"):
		var relative := script_path.trim_prefix("res://")
		var owned := false
		for prefix in prefixes:
			owned = owned or relative.begins_with(prefix)
		if not owned:
			unowned.append(relative)
	assert_true(_scripts_under("res://src").size() > 100, "fixture: the production scripts were found")
	assert_eq(unowned.size(), 0, "every production script has an owning area (%s)" % ", ".join(unowned))


func _scripts_under(root: String) -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(root)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".gd"):
			found.append(root.path_join(file))
	for child in dir.get_directories():
		found.append_array(_scripts_under(root.path_join(child)))
	return found

func test_nan_never_passes_near() -> void:
	var probe := _NanCaseSuite.new()
	await probe.run()
	assert_eq(probe.failures.size(), 1, "NaN fails assert_near")
