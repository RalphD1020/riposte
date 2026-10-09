class_name MatchScreen
extends Control

## The running duel. Each frame the FixedTickDriver decides how many ticks
## to run; each tick steps the MatchSession, projects one
## PresentationSnapshot, and pushes it (with that tick's events) to the
## MatchPresenter and HUD; then the presenter renders with the driver's
## alpha. Hitstop holds the driver, never the simulation (HITSTOP-001).
## Keyboard, mouse, and touch merge into one HumanInputState. Pause, focus
## loss, and the portrait prompt stop the clock and cancel held input
## without attacking; resuming never catches up the backlog.
##
## See also: /docs/concepts/simulation.md
## See also: /docs/concepts/controls.md

var app: RiposteApp
var session: MatchSession
var driver: FixedTickDriver = FixedTickDriver.new()
var human: HumanController = HumanController.new()
var presenter: MatchPresenter
var hud: DuelHud
var touch: TouchControls
var pause_overlay: PauseOverlay
var debug_overlay: DebugOverlay
var tutorial: TutorialTracker
## The once-per-set introduction, while it plays. The clock is stopped for
## its whole length, so no tick runs and nothing authoritative can differ.
var intro: SetIntroDirector
var _user_paused: bool = false
var _finished: bool = false
var _touch_layout: bool = false


func bind(riposte_app: RiposteApp) -> MatchScreen:
	app = riposte_app
	return self


func _ready() -> void:
	name = "MatchScreen"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var config := app.match_config
	var kits: DuelKits = null
	if config != null:
		session = MatchComposer.compose(config, human, app.telemetry)
		kits = DuelKits.resolve(app.kit_catalog, config.rules, app.fighter_skins(), app.weapon_skins())
		if kits.is_complete():
			kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	if session == null or not kits.is_complete():
		push_error("MatchScreen: cannot compose the match (invalid rules or missing presentation kits)")
		session = null
		app.go_to(AppScreen.Id.MAIN_MENU)
		return
	var options := app.presentation_options()
	_touch_layout = options.touch_layout
	## Put the local player at the bottom of the screen. The world does not
	## move; only this viewer does (SIDE-001).
	app.camera_rig.look_from(session.state.fighter(config.human_slot).side)
	presenter = MatchPresenter.create(kits, options, app.camera_rig, config.rules.platform_radius, config.rules.edge_warning_inset, SnapshotProjector.project(session.state, config.rules))
	presenter.hitstop_requested.connect(driver.hold)
	presenter.slow_motion_requested.connect(driver.slow_motion)
	app.presentation_mount.add_child(presenter)
	_build_ui(config)
	hud.reduced_motion = options.reduced_motion
	if options.captions:
		presenter.audio().caption_requested.connect(hud.show_caption)
	if app.consume_set_intro():
		intro = presenter.create_intro(app.camera_rig.camera())
		intro.card_requested.connect(hud.show_card)
		intro.finished.connect(_on_intro_finished)
		_sync_clock()
	if config.mode == MatchConfig.Mode.TRAINING:
		tutorial = TutorialTracker.create(config.human_slot)
		_show_tutorial_step()
	hud.update(presenter.current_snapshot())
	get_viewport().gui_release_focus()
	resized.connect(relayout)
	relayout()
	app.telemetry.record_product(ProductEvents.MATCH_STARTED, {
		ProductEvents.PROP_MODE: int(config.mode),
		ProductEvents.PROP_DIFFICULTY: int(config.cpu_difficulty),
	})


func _exit_tree() -> void:
	human.input.cancel_all()
	if presenter != null:
		presenter.detach_and_dispose()
		presenter = null


func _process(delta: float) -> void:
	advance_frame(delta)


## One display frame: poll held keys, run due ticks, render. Tests drive the
## real loop by calling this with a chosen delta.
func advance_frame(delta: float) -> void:
	if session == null or presenter == null:
		return
	if is_intro_playing() and not _user_paused:
		intro.advance(delta)
	if not driver.paused:
		var keys := InputActions.move_vector()
		human.input.set_key_axis(keys.x, keys.y)
	if not _finished:
		var steps := driver.consume(delta)
		for _i in steps:
			_advance_tick()
			if _finished:
				break
	presenter.render(driver.alpha(), delta)
	debug_overlay.update(presenter.current_snapshot(), Engine.get_frames_per_second())


func is_paused() -> bool:
	return driver.paused


func is_finished() -> bool:
	return _finished


func is_intro_playing() -> bool:
	return intro != null and is_instance_valid(intro) and not intro.is_done()


func skip_intro() -> void:
	if is_intro_playing():
		intro.finish()


func _on_intro_finished() -> void:
	intro = null
	_sync_clock()


func pause() -> void:
	if session == null or _finished or _user_paused:
		return
	_user_paused = true
	pause_overlay.open()
	_sync_clock()


func resume() -> void:
	if not _user_paused:
		return
	_user_paused = false
	pause_overlay.close()
	get_viewport().gui_release_focus()
	_sync_clock()


func quit_to_menu() -> void:
	_finished = true
	app.quit_match()


func relayout() -> void:
	if session == null:
		return
	var insets := app.safe_insets()
	hud.layout_insets(insets)
	touch.set_insets(insets)


func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	var tapped := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if is_intro_playing() and (tapped or event.is_action_pressed(InputActions.PAUSE) or event.is_action_pressed(InputActions.ATTACK)):
		## Any deliberate press skips the intro; it never starts an attack.
		get_viewport().set_input_as_handled()
		skip_intro()
		return
	if event.is_action_pressed(InputActions.PAUSE):
		get_viewport().set_input_as_handled()
		if _user_paused:
			pause_overlay.back()
		else:
			pause()
		return
	if event.is_action_pressed(InputActions.TOGGLE_DEBUG) and OS.is_debug_build():
		get_viewport().set_input_as_handled()
		debug_overlay.visible = not debug_overlay.visible
		## The numbers and the vectors are one mode. Reading "closing speed
		## 4.2" without seeing which way the tip is going is half the picture,
		## and splitting them across two keys only ever meant forgetting one.
		presenter.debug_vectors().visible = debug_overlay.visible
		return
	if driver.paused or _finished or event.is_echo() or not event.is_action(InputActions.ATTACK):
		return
	get_viewport().set_input_as_handled()
	var source := HumanInputState.SOURCE_POINTER if event is InputEventMouseButton else HumanInputState.SOURCE_KEY
	if event.is_pressed():
		human.input.attack_down(source)
	else:
		human.input.attack_up(source)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			pause()


func _advance_tick() -> void:
	var phase_before := session.state.phase
	var events := session.step()
	if session.state.phase != phase_before:
		_on_phase_transition(phase_before, session.state.phase)
	var snapshot := SnapshotProjector.project(session.state, session.config.rules)
	presenter.push(snapshot, events)
	hud.update(snapshot)
	debug_overlay.observe(events)
	if tutorial != null and tutorial.observe(session.state, events):
		_show_tutorial_step()
	if session.is_finished():
		_finished = true
		human.input.cancel_all()
		touch.set_enabled(false)
		app.finish_match(session)


## Flush stale input at every round-boundary phase transition so no buffered
## attack, held state, or tap history leaks across rounds (INPUT-002).
func _on_phase_transition(_from: MatchPhase.Id, _to: MatchPhase.Id) -> void:
	human.input.begin_input_epoch()
	touch.reset()


## Stopped by the user or by the rotate prompt. Resuming drops the backlog
## so a long pause never fast-forwards the duel.
func _sync_clock() -> void:
	var stopped := _user_paused or is_intro_playing()
	if stopped and not driver.paused:
		human.input.cancel_all()
	if driver.paused and not stopped:
		driver.clear_backlog()
	driver.paused = stopped
	touch.set_enabled(not stopped and not _finished)


func _show_tutorial_step() -> void:
	hud.show_prompt(AppCopy.tutorial_title(tutorial.step), AppCopy.tutorial_detail(tutorial.step))
	_cue_partner()
	if tutorial.is_complete():
		app.telemetry.record_product(ProductEvents.TUTORIAL_COMPLETED)


## Ask the training partner for the beat the current lesson needs. Done here
## rather than inside either of them: the tracker only watches, the partner
## only types commands, and the drill script is the screen's business.
func _cue_partner() -> void:
	for controller in session.controllers:
		var partner := controller as TrainingDummyController
		if partner == null:
			continue
		match tutorial.step:
			TutorialTracker.Step.SWEET_SPOT:
				partner.beat = TrainingDummyController.Beat.BIG_SWING
			TutorialTracker.Step.MOMENTUM:
				partner.beat = TrainingDummyController.Beat.PACE
			_:
				partner.beat = TrainingDummyController.Beat.SPAR


func _build_ui(config: MatchConfig) -> void:
	var mine := session.state.fighter(config.human_slot).side
	hud = DuelHud.create(
		HudCopy.sided(AppCopy.YOU, mine),
		HudCopy.sided(AppCopy.opponent_label(config), DuelSide.other(mine)),
		config.human_slot,
		mine
	)
	hud.pause_pressed.connect(pause)
	add_child(hud)
	touch = TouchControls.new()
	touch.opacity = app.settings.opacity_value()
	touch.exclusions.append(hud.pause_button())
	touch.move_changed.connect(_on_touch_move)
	touch.attack_pressed.connect(_on_touch_attack_pressed)
	touch.attack_released.connect(_on_touch_attack_released)
	touch.canceled.connect(human.input.cancel_all)
	add_child(touch)
	if _touch_layout:
		touch.reveal()
	debug_overlay = DebugOverlay.create()
	debug_overlay.describe(session.config.rules.fighter, session.config.rules.weapon)
	add_child(debug_overlay)
	pause_overlay = PauseOverlay.create(app)
	pause_overlay.resume_requested.connect(resume, CONNECT_DEFERRED)
	pause_overlay.quit_requested.connect(quit_to_menu, CONNECT_DEFERRED)
	add_child(pause_overlay)


func _on_touch_move(vector: Vector2, active: bool) -> void:
	human.input.set_touch_axis(vector.x, vector.y, active)


func _on_touch_attack_pressed() -> void:
	human.input.attack_down(HumanInputState.SOURCE_TOUCH)
	presenter.haptics().pulse(Haptics.ATTACK)


func _on_touch_attack_released() -> void:
	human.input.attack_up(HumanInputState.SOURCE_TOUCH)
