extends Node

## Headless harness scene root. Runs every suite from the first _process()
## after the SceneTree is active, so nodes added by tests are real tree members.
## The runner is a coroutine; this root waits for it, then lets queued frees
## settle before quitting with the runner's exit code.
##
## Stopped voices are released by the audio thread and then freed on the main
## thread's next AudioServer update, so for a moment the tree holds objects no
## test still owns. The at-exit ObjectDB leak check cannot tell those from a
## real leak, and it stays strict for everything else.
##
## Headless frames outrun the mixer — `--fixed-fps` fixes the delta, not the
## wall clock — so waiting on frames alone would conclude nothing. This waits
## on the live object count instead: a floor of real time first, because that
## much is known to be needed, then polling for as long as the count is still
## falling. A flat sleep is the one shape that cannot be right everywhere: the
## same number is wasted time on this machine and too short on a slower one,
## and only the wasted time is visible. The timeout is a bound, not the
## mechanism.
##
## Invoked: godot --headless --fixed-fps 60 --path <game> res://tests/harness/run_headless.tscn
##
## See also: /docs/reference/testing.md

## Real time the mixer is known to need before it has released anything.
const AUDIO_SETTLE_MSEC := 120
## Then poll, in real-time slices, until the count holds still this many times.
const SETTLE_POLL_MSEC := 10
const SETTLE_STABLE_POLLS := 3
## A machine this slow has a problem the leak check is not going to diagnose.
const SETTLE_TIMEOUT_MSEC := 2000

var _started: bool = false


func _process(_delta: float) -> void:
	if _started:
		return
	_started = true
	var runner := HeadlessRunner.new()
	var exit_code: int = await runner.run()
	await get_tree().process_frame
	OS.delay_msec(AUDIO_SETTLE_MSEC)
	await _settle_freed_objects()
	await get_tree().process_frame
	get_tree().quit(exit_code)


## Wait while the live object count is still falling. Each pass gives the
## audio thread real time to release, then gives the main thread a frame to
## free what was released.
func _settle_freed_objects() -> void:
	var deadline := Time.get_ticks_msec() + SETTLE_TIMEOUT_MSEC
	var stable := 0
	var last := -1
	while stable < SETTLE_STABLE_POLLS and Time.get_ticks_msec() < deadline:
		OS.delay_msec(SETTLE_POLL_MSEC)
		await get_tree().process_frame
		var live := int(Performance.get_monitor(Performance.OBJECT_COUNT))
		stable = stable + 1 if live == last else 0
		last = live
