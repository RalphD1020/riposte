extends SceneTree

## TOOL-TEST-002 fixture. Not in HeadlessRunner.SUITES; only `test:tooling`
## runs it. Emits a SCRIPT ERROR, then fakes a PASS and exit 0. The Node
## wrapper MUST still classify the run as a failure.
##
## The error lives in a helper: a runtime error aborts only the erroring
## function, so `_initialize` still reaches `quit()` instead of idling.


func _initialize() -> void:
	_emit_script_error()
	print("PASS  TOOL-FIXTURE-002")
	print(
		'RIPOSTE_RESULT {"kind":"godot-test","status":"PASS","failure_category":"","passed":1,"failed":0,"suites":1,"assertions":1,"errors":0}'
	)
	quit(0)


func _emit_script_error() -> void:
	var empty: Array[int] = []
	print(empty[99])
