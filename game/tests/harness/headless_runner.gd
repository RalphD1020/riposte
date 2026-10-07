class_name HeadlessRunner
extends RefCounted

## Runs every behavioral suite and prints one RIPOSTE_RESULT line.
##
## A suite fails when any assertion fails, any case records zero assertions,
## or the suite leaks orphan nodes. `RIPOSTE_SUITE=<name>` runs one suite.
##
## See also: /docs/reference/testing.md
## See also: /docs/reference/godot.md

const SUITES: PackedStringArray = [
	"res://tests/harness/test_harness.gd",
	"res://tests/domain/test_math.gd",
	"res://tests/domain/test_command.gd",
	"res://tests/domain/test_rules.gd",
	"res://tests/domain/test_scaling.gd",
	"res://tests/domain/test_invariants.gd",
	"res://tests/domain/test_side.gd",
	"res://tests/domain/test_stamina.gd",
	"res://tests/domain/test_fuzz.gd",
	"res://tests/domain/test_movement.gd",
	"res://tests/domain/test_facing.gd",
	"res://tests/domain/test_attack.gd",
	"res://tests/domain/test_burst.gd",
	"res://tests/domain/test_commitment.gd",
	"res://tests/domain/test_collision.gd",
	"res://tests/domain/test_body_push.gd",
	"res://tests/domain/test_contact.gd",
	"res://tests/domain/test_damage.gd",
	"res://tests/domain/test_point_strike.gd",
	"res://tests/domain/test_lethality.gd",
	"res://tests/domain/test_semantics.gd",
	"res://tests/domain/test_round.gd",
	"res://tests/domain/test_replay.gd",
	"res://tests/domain/test_symmetry.gd",
	"res://tests/application/test_input.gd",
	"res://tests/application/test_driver.gd",
	"res://tests/application/test_settings.gd",
	"res://tests/application/test_tutorial.gd",
	"res://tests/application/test_session.gd",
	"res://tests/application/test_cpu.gd",
	"res://tests/application/test_edge_safety.gd",
	"res://tests/presentation/test_theme.gd",
	"res://tests/presentation/test_kits.gd",
	"res://tests/presentation/test_snapshot.gd",
	"res://tests/presentation/test_camera.gd",
	"res://tests/presentation/test_feedback.gd",
	"res://tests/presentation/test_presenter.gd",
	"res://tests/presentation/test_hud.gd",
	"res://tests/application/test_app_shell.gd",
	"res://tests/application/test_app_e2e.gd",
]


func run() -> int:
	var only := OS.get_environment("RIPOSTE_SUITE")
	var passed := 0
	var failed := 0
	var executed := 0
	var assertions := 0
	for path in SUITES:
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
		if only != "" and suite.suite_name != only:
			continue
		executed += 1
		var orphans_before := _orphan_count()
		await suite.run()
		await _settle()
		var leaked := _orphan_count() - orphans_before
		if leaked > 0:
			suite.failures.append("leaked %d orphan node(s)" % leaked)
			Node.print_orphan_nodes()
		assertions += suite.assertion_count
		if suite.failures.is_empty():
			print("PASS  %s (%d cases, %d assertions)" % [suite.suite_name, suite.case_count, suite.assertion_count])
			passed += 1
		else:
			print("FAIL  %s" % suite.suite_name)
			for message in suite.failures:
				print("      - %s" % message)
			failed += 1
	if executed == 0:
		print("FAIL  harness ran zero suites (RIPOSTE_SUITE=%s)" % only)
		_print_result("FAIL", "HARNESS_FAILURE", 0, 1, 0, 0)
		return 1
	var status := "FAIL" if failed > 0 else "PASS"
	print("%d passed, %d failed, %d assertions" % [passed, failed, assertions])
	_print_result(status, "TEST_FAILURE" if failed > 0 else "", passed, failed, executed, assertions)
	return 1 if failed > 0 else 0


func _print_result(status: String, category: String, passed: int, failed: int, suites: int, assertions: int) -> void:
	var result := {
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
