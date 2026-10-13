class_name HeadlessRunner
extends RefCounted

## Runs the behavioral suites and prints one RIPOSTE_RESULT line.
##
## A suite fails when any assertion fails, any case records zero assertions,
## or the suite leaks orphan nodes. `RIPOSTE_SUITE=<name>[,<name>…]` runs only
## those suites, whatever their tier.
##
## Suites, tiers and budgets live in one manifest (`tests/suite_manifest.json`,
## TEST-TIER-001), which `test:changed` and `test:focused` read too. Four
## processes, each with its own result (`RIPOSTE_TIER`): `gate` (the default,
## `pnpm test`) runs every correctness suite — the fast, focused and gate
## sizes, the CPU's laws included; `balance` (`pnpm test:balance`) the CPU
## balance smoke; `accept` (`pnpm test:balance:accept`) the held-out ladder;
## `ship` (`pnpm test:contact:ship`) the long contact corpora. A slow audit
## therefore never makes the correctness run look hung; `verify` runs the gate
## and the smoke. Every suite is timed; one over its budget is reported, never
## failed — a budget makes growth visible, it is not a target.
##
## See also: /docs/reference/testing.md
## See also: /docs/reference/godot.md

const MANIFEST_PATH := "res://tests/suite_manifest.json"
const TIER_GATE := "gate"
const TIER_BALANCE := "balance"
const TIER_ACCEPT := "accept"
const TIER_SHIP := "ship"
## The manifest sizes the gating run covers.
const GATING := ["fast", "focused", "gate"]

static var _manifest: Dictionary = {}


## The parsed manifest (read once).
static func manifest() -> Dictionary:
	if _manifest.is_empty():
		_manifest = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	return _manifest


## Every registered suite path, in manifest order.
static func suite_paths() -> PackedStringArray:
	var paths := PackedStringArray()
	for registered: Dictionary in manifest()["suites"]:
		paths.append(String(registered["path"]))
	return paths


## The manifest entry for `path`, or empty when it is not registered.
static func entry(path: String) -> Dictionary:
	for candidate: Dictionary in manifest()["suites"]:
		if String(candidate["path"]) == path:
			return candidate
	return {}


## Whether `path` runs in `tier` (`gate` when unset or unknown).
static func in_tier(path: String, tier: String) -> bool:
	var size := String(entry(path).get("tier", ""))
	if tier == TIER_BALANCE or tier == TIER_ACCEPT or tier == TIER_SHIP:
		return size == tier
	return GATING.has(size)

func run() -> int:
	var only := OS.get_environment("RIPOSTE_SUITE")
	var tier := OS.get_environment("RIPOSTE_TIER")
	var passed := 0
	var failed := 0
	var executed := 0
	var assertions := 0
	var benchmarks_missed := 0
	var over_budget := 0
	for path in suite_paths():
		if only == "" and not in_tier(path, tier):
			continue
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("FAIL  cannot load %s" % path)
			executed += 1
			failed += 1
			continue
		var suite := script.new() as TestCase
		if suite == null:
			print("FAIL  %s does not extend TestCase" % path)
			executed += 1
			failed += 1
			continue
		if only != "" and not only.split(",").has(suite.suite_name):
			continue
		executed += 1
		var orphans_before := _orphan_count()
		var started := Time.get_ticks_msec()
		await suite.run()
		var elapsed := Time.get_ticks_msec() - started
		await _settle()
		var leaked := _orphan_count() - orphans_before
		if leaked > 0:
			suite.failures.append("leaked %d orphan node(s)" % leaked)
			Node.print_orphan_nodes()
		assertions += suite.assertion_count
		var outcome := verdict(suite)
		if outcome == Verdict.PASS:
			print("PASS  %s (%d cases, %d assertions, %.1f s)" % [suite.suite_name, suite.case_count, suite.assertion_count, float(elapsed) / 1000.0])
			passed += 1
		elif outcome == Verdict.BENCHMARK_MISSED:
			print("BENCH %s — not gating: %s" % [suite.suite_name, suite.benchmark_reason])
			for message in suite.failures:
				print("      ~ %s" % message)
			benchmarks_missed += 1
			passed += 1
		else:
			print("FAIL  %s" % suite.suite_name)
			for message in suite.failures:
				print("      - %s" % message)
			failed += 1
		var budget := int(entry(path).get("budget_ms", 0))
		if budget > 0 and elapsed > budget:
			print("SLOW  %s took %d ms, over its %d ms budget" % [suite.suite_name, elapsed, budget])
			over_budget += 1
	if executed == 0:
		print("FAIL  harness ran zero suites (RIPOSTE_SUITE=%s, RIPOSTE_TIER=%s)" % [only, tier])
		_print_result("FAIL", "HARNESS_FAILURE", 0, 1, 0, 0)
		return 1
	var status := "FAIL" if failed > 0 else "PASS"
	print("%d passed, %d failed, %d assertions, %d benchmark(s) below target, %d over budget" % [passed, failed, assertions, benchmarks_missed, over_budget])
	_print_result(status, "TEST_FAILURE" if failed > 0 else "", passed, failed, executed, assertions, benchmarks_missed, over_budget)
	return 1 if failed > 0 else 0


enum Verdict { PASS, BENCHMARK_MISSED, FAIL }


## A benchmark suite that missed its target only through failed assertions is
## reported and does not gate; anything else that failed — including a
## benchmark's zero-assertion case or leak — fails the run.
static func verdict(suite: TestCase) -> Verdict:
	if suite.failures.is_empty():
		return Verdict.PASS
	if suite.benchmark_reason != "" and suite.failures.size() == suite.assertion_failure_count:
		return Verdict.BENCHMARK_MISSED
	return Verdict.FAIL


func _print_result(status: String, category: String, passed: int, failed: int, suites: int, assertions: int, benchmarks_missed: int = 0, over_budget: int = 0) -> void:
	var result := {
		"benchmarks_below_target": benchmarks_missed,
		"over_budget": over_budget,
		"kind": "godot-test",
		"status": status,
		"failure_category": category,
		"passed": passed,
		"failed": failed,
		"suites": suites,
		"assertions": assertions,
		"errors": failed,
	}
	print("RIPOSTE_RESULT %s" % JSON.stringify(result))


func _settle() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	await tree.process_frame
	await tree.process_frame


func _orphan_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))
