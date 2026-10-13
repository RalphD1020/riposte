extends SceneTree

## Performance diagnostics: what one 60 Hz frame of a real duel costs on this
## machine, split into the authoritative step, both CPU controllers, the
## presenter's push and render, and the whole process frame (which includes
## the skeleton modifiers and IK the presenter drives). Read against the
## budgets in /docs/architecture/PERFORMANCE.md. Read-only; never a gate.
##
## Run: godot --headless --path game --script res://tools/perf_report.gd [-- --seeds=N]
##
## Headless means the dummy renderer, so GPU cost is absent, and the editor
## binary is a debug build: these are desktop upper bounds for script cost,
## not device numbers. Device budgets are measured on release builds on the
## device matrix.
##
## See also: /docs/architecture/PERFORMANCE.md

const SEEDS: PackedInt64Array = [101, 202, 303, 404, 505, 606, 707, 808]
const DEFAULT_SEEDS := 4
const MAX_TICKS := 60 * 60 * 6
const FRAME := 1.0 / 60.0

var _rules: DuelRules
var _kits: DuelKits
var _seeds := DEFAULT_SEEDS
var _index := -1
var _session: MatchSession
var _presenter: MatchPresenter
var _root: Node3D
var _ticks := 0
var _sim := PackedInt64Array()
var _sim_held := PackedInt64Array()
var _sim_apart := PackedInt64Array()
var _cpu := PackedInt64Array()
var _push := PackedInt64Array()
var _render := PackedInt64Array()
var _frame := PackedInt64Array()
var _last_frame_start := 0
var _measured_frame := false
## The same matches with no presenter mounted, so the frame row is the engine
## floor and the difference is what presentation costs end to end.
var _sim_only := false


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--seeds="):
			_seeds = clampi(int(arg.trim_prefix("--seeds=")), 1, SEEDS.size())
		elif arg == "--sim-only":
			_sim_only = true
	Engine.max_fps = 0
	OS.low_processor_usage_mode_sleep_usec = 0
	_rules = StandardDuelRules.create()
	_kits = DuelKits.resolve(RiposteKits.build_catalog(), _rules)
	_next_match()


## The engine's process-time monitor is the worst frame of each second, so a
## frame is measured here instead: from one frame's start to the next, with
## the frame limiter and headless idle sleep off, which includes the nodes processed after this
## script (clips, skeleton modifiers, IK) and the dummy renderer.
func _process(_delta: float) -> bool:
	var frame_started := Time.get_ticks_usec()
	if _measured_frame:
		_frame.append(frame_started - _last_frame_start)
	_last_frame_start = frame_started
	return _frame_body()


func _frame_body() -> bool:
	if _session.is_finished() or _ticks >= MAX_TICKS:
		if not _next_match():
			_print()
			return true
	var before := _session.events.size()
	var started := Time.get_ticks_usec()
	_session.step()
	var stepped := Time.get_ticks_usec() - started
	_sim.append(_session.last_step_usec)
	if _session.state.blade_contact.hold_count() > 0:
		_sim_held.append(_session.last_step_usec)
	else:
		_sim_apart.append(_session.last_step_usec)
	_cpu.append(stepped - _session.last_step_usec)
	_ticks += 1
	_measured_frame = true
	if _sim_only:
		return false
	var events: Array[DuelEvent] = []
	for index in range(before, _session.events.size()):
		events.append(_session.events[index])
	started = Time.get_ticks_usec()
	_presenter.push(SnapshotProjector.project(_session.state, _rules), events)
	_push.append(Time.get_ticks_usec() - started)
	started = Time.get_ticks_usec()
	_presenter.render(1.0, FRAME)
	_render.append(Time.get_ticks_usec() - started)
	return false


func _next_match() -> bool:
	if _presenter != null:
		_presenter.detach_and_dispose()
		_root.queue_free()
	_index += 1
	_measured_frame = false
	if _index >= _seeds:
		return false
	var match_seed := SEEDS[_index]
	var config := MatchConfig.quick_play(MatchConfig.Difficulty.HARD, match_seed)
	var controllers: Array[FighterController] = []
	for slot in 2:
		controllers.append(CpuController.create(config.rules, CpuProfile.for_difficulty(MatchConfig.Difficulty.HARD), match_seed, slot))
	_session = MatchSession.create(config, controllers)
	_ticks = 0
	if _sim_only:
		return true
	_root = Node3D.new()
	root.add_child(_root)
	_presenter = MatchPresenter.create(_kits, PresentationOptions.new(), null, _rules.platform_radius, _rules.edge_warning_inset, SnapshotProjector.project(_session.state, _rules))
	_root.add_child(_presenter)
	return true


func _print() -> void:
	print("\nFrame cost, rules v%d, %d Hard-vs-Hard matches, %d ticks (µs; headless debug build, no GPU)" % [_rules.version, _seeds, _sim.size()])
	print("  %-34s %8s %8s %8s %8s" % ["", "mean", "p50", "p99", "max"])
	_row("authoritative step", _sim)
	_row("  with swords held in contact", _sim_held)
	_row("  with swords apart", _sim_apart)
	_row("both CPU controllers", _cpu)
	if _sim_only:
		_row("whole process frame (no presenter)", _frame)
		return
	_row("presenter push (feedback, audio)", _push)
	_row("presenter render (pose, camera)", _render)
	var scripting := PackedInt64Array()
	for index in _push.size():
		scripting.append(_push[index] + _render[index])
	_row("presentation scripting", scripting)
	_row("whole process frame", _frame)
	print("  budget: presentation scripting < 1000 µs; normal frame < 12000 µs")


func _row(label: String, samples: PackedInt64Array) -> void:
	var sorted := samples.duplicate()
	sorted.sort()
	var total := 0
	for value in sorted:
		total += value
	var count := sorted.size()
	print("  %-34s %8.0f %8d %8d %8d" % [label, float(total) / count, sorted[floori(count * 0.5)], sorted[mini(count - 1, int(count * 0.99))], sorted[count - 1]])
