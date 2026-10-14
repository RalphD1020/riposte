extends SceneTree

## P0 profile: where one authoritative CPU-vs-CPU tick spends its time, ranked.
## The simulation cannot read a clock (SIM-001), so the sections are timed from
## outside, through the seams the duel already has: the collision sweep and
## the persistent-contact solver are substituted by timing subclasses, and each
## CPU is wrapped as a controller. Nothing here ships; shipping code carries no
## timers (the in-game monitor is `Riposte/SimStepUs`, measured around the
## step). Averages over every tick of the corpus, never single calls; the
## editor binary is a debug build, so these are upper bounds — release builds
## on target hardware own the absolute numbers.
##
## Run: godot --headless --path game --script res://tools/profile_report.gd
##
## See also: /docs/architecture/PERFORMANCE.md

## Clear of every CPU corpus (`CpuLadder`).
const SEEDS: Array[int] = [401, 402, 403]
const MAX_TICKS := 6000


class TimedCollision extends CollisionSystem:
	var samples := PackedInt64Array()

	func detect(state: MatchState, start: Array[FighterPose], finish: Array[FighterPose], rules: DuelRules, manifold: SwordContactSet, report: ContactReport, holds: bool = true, bodies: bool = true) -> void:
		var t := Time.get_ticks_usec()
		super.detect(state, start, finish, rules, manifold, report, holds, bodies)
		samples.append(Time.get_ticks_usec() - t)


class TimedSolver extends RigidContactSolver:
	var velocity := PackedInt64Array()
	var position := PackedInt64Array()

	func solve_velocity(state: MatchState, rules: DuelRules, warm: bool = false) -> float:
		var t := Time.get_ticks_usec()
		var impulse := super.solve_velocity(state, rules, warm)
		velocity.append(Time.get_ticks_usec() - t)
		return impulse

	func project(state: MatchState, rules: DuelRules) -> void:
		var t := Time.get_ticks_usec()
		super.project(state, rules)
		position.append(Time.get_ticks_usec() - t)


class TimedCpu extends FighterController:
	var inner: CpuController
	var samples := PackedInt64Array()

	func command_for(state: MatchState, slot: int) -> PlayerCommand:
		var t := Time.get_ticks_usec()
		var command := inner.command_for(state, slot)
		samples.append(Time.get_ticks_usec() - t)
		return command


func _initialize() -> void:
	var step := PackedInt64Array()
	var collision := PackedInt64Array()
	var velocity := PackedInt64Array()
	var position := PackedInt64Array()
	var cpu := PackedInt64Array()
	var ticks := 0
	for seed_value in SEEDS:
		var config := MatchConfig.quick_play(MatchConfig.Difficulty.HARD, seed_value)
		var cpus: Array[TimedCpu] = []
		var controllers: Array[FighterController] = []
		for slot in 2:
			var wrapper := TimedCpu.new()
			wrapper.inner = CpuController.create(config.rules, CpuProfile.hard(), seed_value, slot)
			cpus.append(wrapper)
			controllers.append(wrapper)
		var session := MatchSession.create(config, controllers)
		var sweep := TimedCollision.new()
		var solver := TimedSolver.new()
		sweep.diagnostics = session.simulation.diagnostics
		solver.diagnostics = session.simulation.diagnostics
		session.simulation.set("_collision", sweep)
		session.simulation.rigid_solver = solver
		while not session.is_finished() and session.state.tick < MAX_TICKS:
			var t := Time.get_ticks_usec()
			session.step()
			step.append(Time.get_ticks_usec() - t)
			ticks += 1
		collision.append_array(sweep.samples)
		velocity.append_array(solver.velocity)
		position.append_array(solver.position)
		for wrapper in cpus:
			cpu.append_array(wrapper.samples)
		print("  · profile seed %d: %d ticks" % [seed_value, session.state.tick])
	var per_tick := func(values: PackedInt64Array) -> float: return float(_sum(values)) / float(maxi(ticks, 1))
	var sections := {
		"session step (all)": per_tick.call(step),
		"CPU controllers (both)": per_tick.call(cpu),
		"collision sweep": per_tick.call(collision),
		"contact velocity solve": per_tick.call(velocity),
		"contact position solve": per_tick.call(position),
	}
	sections["rest of the simulation"] = float(sections["session step (all)"]) - float(sections["CPU controllers (both)"]) - float(sections["collision sweep"]) - float(sections["contact velocity solve"]) - float(sections["contact position solve"])
	print("\nper tick, mean over %d ticks (debug build, µs):" % ticks)
	var names := sections.keys()
	names.sort_custom(func(a: String, b: String) -> bool: return float(sections[a]) > float(sections[b]))
	for name: String in names:
		print("  %-26s %8.1f" % [name, float(sections[name])])
	print("  step p95 %d µs, max %d µs; collision calls/tick %.1f, velocity solves/tick %.1f" % [_p95(step), _max(step), float(collision.size()) / ticks, float(velocity.size()) / ticks])
	print("PROFILE_RESULT %s" % JSON.stringify(sections))
	quit()


func _sum(values: PackedInt64Array) -> int:
	var total := 0
	for v in values:
		total += v
	return total


func _p95(values: PackedInt64Array) -> int:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int(sorted.size() * 0.95)] if sorted.size() > 0 else 0


func _max(values: PackedInt64Array) -> int:
	var top := 0
	for v in values:
		top = maxi(top, v)
	return top
