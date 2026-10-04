extends Node

## Headless harness scene root. Runs every suite from the first _process()
## after the SceneTree is active, so nodes added by tests are real tree members.
## The runner is a coroutine; this root waits for it, then lets queued frees
## settle before quitting with the runner's exit code.
##
## Stopped voices are released by the audio thread and then freed on the main
## thread's next AudioServer update. Headless frames outrun the mixer, so the
## root gives it real time before exit; the at-exit ObjectDB leak check stays
## strict for everything else.
##
## Invoked: godot --headless --fixed-fps 60 --path <game> res://tests/harness/run_headless.tscn
##
## See also: /docs/reference/testing.md

const AUDIO_SETTLE_MSEC := 120

var _started: bool = false


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	var runner := HeadlessRunner.new()
	var exit_code: int = await runner.run()
	await get_tree().process_frame
	OS.delay_msec(AUDIO_SETTLE_MSEC)
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().quit(exit_code)
