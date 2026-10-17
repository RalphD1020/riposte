extends SceneTree

## Application capture of the glance the app test already drives.
## `main.tscn`, the product camera, the HUD, and `FixedTickDriver.alpha`.
## Not the bare presenter in `capture_clash.gd`.
##
## Windowed, not `--headless`:
##
##   godot --path game --rendering-method gl_compatibility --resolution 1280x720 -s res://tools/capture_app_clash.gd
##
## The stepping frame is whatever alpha the clock has after it consumes the
## contact tick. The next frame is half a tick, so the product interpolates
## if the accumulator was empty. The sidecar records those alphas. It does
## not change the solver or the interpolation.


const FRAME := SimulationTimebase.TICK_SECONDS

var _out: String = ""


func _init() -> void:
	_out = ProjectSettings.globalize_path("res://../.reports/clash")
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="):
			_out = argument.trim_prefix("--out=")
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var driver := AppDriver.boot(7)
	await process_frame
	var rules := StandardDuelRules.create()
	driver.app.compose_session = func(config: MatchConfig, human: HumanController, sink: TelemetrySink) -> MatchSession:
		config.seed_value = 7
		var controllers: Array[FighterController] = [human, ScenarioController.standing()]
		return MatchSession.create(config, controllers, sink)
	driver.app.start_quick_play()
	await process_frame
	var screen := driver.match_screen()
	screen.skip_intro()
	driver.run_until(screen, func() -> bool: return screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	var state := screen.session.state
	DuelFixture.place(state.fighter(0), 0.0, 0.0, 0.0)
	state.fighter(0).weapon.reset(-rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(state.fighter(1), 2.0, -0.3, PI)
	state.fighter(1).weapon.reset(1.2)
	driver.tap_attack()
	var contact: DuelEvent = null
	var seen := screen.session.events.size()
	for _t in 40:
		var tick := state.tick
		screen.advance_frame(FRAME)
		if state.tick == tick:
			continue
		while seen < screen.session.events.size():
			var event: DuelEvent = screen.session.events[seen]
			seen += 1
			if contact == null and event.type == DuelEventTypes.BLADE_CONTACT:
				contact = event
		if contact != null:
			break
	var alpha_after_step := screen.driver.alpha()
	var card_up := screen.round_start.is_showing()
	await _grab("app_glance_after_step")
	screen.advance_frame(FRAME * 0.5)
	var alpha_half := screen.driver.alpha()
	var tick_after_half := state.tick
	await _grab("app_glance_half_frame")
	## The "FIGHT!" hold is 0.45 s of display time. This contact is reached
	## before that hold ends, so the card covers the join. Clearing it here
	## does not step the duel. The next frame is the same pose without the card.
	screen.round_start.clear()
	screen.advance_frame(0.0)
	await _grab("app_glance_half_frame_card_cleared")
	var reading := ""
	var clang := ""
	var impulse := 0.0
	var energy := 0.0
	var arrested := false
	if contact != null:
		var control := rules.combatant(0).weapon.control_speed
		reading = String(ContactReading.classify(contact, control, control))
		clang = contact.text(DuelEventKeys.CONTACT_CLASS)
		impulse = contact.number(DuelEventKeys.IMPULSE)
		energy = contact.number(DuelEventKeys.ENERGY)
		arrested = bool(contact.data[DuelEventKeys.ARRESTED_0])
	var gap := ContactGauge.blades(rules, state).x
	var lines := PackedStringArray([
		"scene: main.tscn through AppDriver",
		"contact: %s" % ("none" if contact == null else "tick %d" % contact.tick),
		"state tick after the half frame: %d" % tick_after_half,
		"class: %s" % clang,
		"reading: %s" % reading,
		"impulse_n_s: %.6f" % impulse,
		"energy_j: %.6f" % energy,
		"arrested_0: %s" % str(arrested),
		"alpha after the stepping frame: %.4f" % alpha_after_step,
		"alpha after a half-tick frame: %.4f" % alpha_half,
		"authoritative surface gap after that half frame (m): %.6f" % gap,
		"hud chrome visible: %s" % str(screen.is_gameplay_chrome_visible()),
		"fight card showing at the contact frame: %s" % str(card_up),
		"phase: %d" % state.fighter(0).weapon.phase,
	])
	var report := FileAccess.open(_out.path_join("app_clash_report.txt"), FileAccess.WRITE)
	report.store_string("\n".join(lines) + "\n")
	report.close()
	print("\n".join(lines))
	driver.shutdown()
	quit()


func _grab(shot_name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join(shot_name + ".png"))
