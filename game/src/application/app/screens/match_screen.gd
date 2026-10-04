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
var _rotate_prompt: Control
var _rotate_dismissed: bool = false
var _rotate_seen: bool = false
var _rotate_blocking: bool = false
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
		kits = DuelKits.resolve(app.kit_catalog, config.rules)
	if session == null or not kits.is_complete():
		push_error("MatchScreen: cannot compose the match (invalid rules or missing presentation kits)")
		session = null
		app.go_to(AppScreen.Id.MAIN_MENU)
		return
	var options := app.presentation_options()
	_touch_layout = options.touch_layout
	presenter = MatchPresenter.create(kits, options, app.camera_rig, config.rules.arena_radius, SnapshotProjector.project(session.state, config.rules))
	presenter.hitstop_requested.connect(driver.hold)
	app.presentation_mount.add_child(presenter)
	_build_ui(config)
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


func dismiss_rotate_prompt() -> void:
	_rotate_dismissed = true
	relayout()


## Touch devices held in portrait get a dismissable rotate prompt (UX §30);
## desktop windows of any shape never do.
static func needs_rotate_prompt(touch_layout: bool, area: Vector2, dismissed: bool) -> bool:
	return touch_layout and area.y > area.x and not dismissed


func relayout() -> void:
	if session == null:
		return
	var insets := app.safe_insets()
	hud.layout_insets(insets)
	touch.set_insets(insets)
	var blocking := needs_rotate_prompt(_touch_layout, size, _rotate_dismissed)
	if blocking and not _rotate_seen:
		_rotate_seen = true
		app.telemetry.record_product(ProductEvents.ORIENTATION_PROMPT_SEEN)
	if blocking != _rotate_blocking:
		_rotate_blocking = blocking
		_rotate_prompt.visible = blocking
		_sync_clock()


func _unhandled_input(event: InputEvent) -> void:
	if session == null:
		return
	if event.is_action_pressed(InputActions.PAUSE):
		get_viewport().set_input_as_handled()
		if _user_paused:
			pause_overlay.back()
		elif not _rotate_blocking:
			pause()
		return
	if event.is_action_pressed(InputActions.TOGGLE_DEBUG) and OS.is_debug_build():
		get_viewport().set_input_as_handled()
		debug_overlay.visible = not debug_overlay.visible
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
	var events := session.step()
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


## Stopped by the user or by the rotate prompt. Resuming drops the backlog
## so a long pause never fast-forwards the duel.
func _sync_clock() -> void:
	var stopped := _user_paused or _rotate_blocking
	if stopped and not driver.paused:
		human.input.cancel_all()
	if driver.paused and not stopped:
		driver.clear_backlog()
	driver.paused = stopped
	touch.set_enabled(not stopped and not _finished)


func _show_tutorial_step() -> void:
	hud.show_prompt(AppCopy.tutorial_title(tutorial.step), AppCopy.tutorial_detail(tutorial.step))
	if tutorial.is_complete():
		app.telemetry.record_product(ProductEvents.TUTORIAL_COMPLETED)


func _build_ui(config: MatchConfig) -> void:
	hud = DuelHud.create(AppCopy.YOU, AppCopy.opponent_label(config), config.human_slot)
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
	add_child(debug_overlay)
	pause_overlay = PauseOverlay.create(app)
	pause_overlay.resume_requested.connect(resume, CONNECT_DEFERRED)
	pause_overlay.quit_requested.connect(quit_to_menu, CONNECT_DEFERRED)
	add_child(pause_overlay)
	_rotate_prompt = Control.new()
	_rotate_prompt.name = "RotatePrompt"
	_rotate_prompt.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_rotate_prompt.mouse_filter = MOUSE_FILTER_STOP
	var sheet := UiKit.sheet(_rotate_prompt)
	var rotate_title := UiKit.heading(sheet, AppCopy.ROTATE_TITLE)
	rotate_title.accessibility_live = AccessibilityServer.LIVE_POLITE
	UiKit.body(sheet, AppCopy.ROTATE_BODY)
	UiKit.button(sheet, AppCopy.CONTINUE_ANYWAY, dismiss_rotate_prompt, &"PrimaryButton")
	_rotate_prompt.visible = false
	add_child(_rotate_prompt)


func _on_touch_move(vector: Vector2, active: bool) -> void:
	human.input.set_touch_axis(vector.x, vector.y, active)


func _on_touch_attack_pressed() -> void:
	human.input.attack_down(HumanInputState.SOURCE_TOUCH)
	presenter.haptics().pulse(Haptics.ATTACK)


func _on_touch_attack_released() -> void:
	human.input.attack_up(HumanInputState.SOURCE_TOUCH)
