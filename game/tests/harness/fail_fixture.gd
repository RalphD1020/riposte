extends SceneTree

## TOOL-TEST-001 fixture. Not in HeadlessRunner.SUITES; only `test:tooling`
## runs it. A failing harness result MUST make the gate exit non-zero.


func _initialize() -> void:
	print("FAIL  TOOL-FIXTURE-001")
	print(
		'RIPOSTE_RESULT {"kind":"godot-test","status":"FAIL","failure_category":"TEST_FAILURE","passed":0,"failed":1,"suites":1,"assertions":1,"errors":1}'
	)
	quit(1)
