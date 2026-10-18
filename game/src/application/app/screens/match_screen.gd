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
var host: LocalMatchHost
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
## "MATCH N … FIGHT!" before every round (PRES-ROUND-START-001).
var round_start: RoundStartDirector
var _user_paused: bool = false
var _finished: bool = false
var _touch_layout: bool = false
## The set has been decided and its deciding round is still playing out: the
## winner keeps control, live, until the match itself ends (Phase 14 —
## `DuelSimulation.accepts_gameplay_input`), and only then is the winner's
## showcase shown. Nothing is fast-forwarded or hidden.
var _set_decided: bool = false
var _horn: SetWinningHorn = SetWinningHorn.new()
var _crowd: CrowdDirector = CrowdDirector.new()


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
		session = app.compose(config, human)
		host = LocalMatchHost.attach(session)
		kits = app.resolve_kits(config)
	if session == null or kits == null or not kits.is_complete():
		push_error("MatchScreen: cannot compose the match (invalid rules or missing presentation kits)")
		session = null
		app.publish_match_music(null)
		app.go_to(AppScreen.Id.MAIN_MENU)
		return
	var options := app.presentation_options()
	_touch_layout = options.touch_layout
	human.input.toggle_charge = app.settings.charge_toggle
	## Put the local player at the bottom of the screen. The world does not
	## move; only this viewer does (SIDE-001).
	app.camera_rig.look_from(session.state.fighter(config.human_slot).side)
	presenter = MatchPresenter.create(kits, options, app.camera_rig, config.rules.platform_radius, config.rules.edge_warning_inset, SnapshotProjector.project(session.state, config.rules))
	presenter.hitstop_requested.connect(driver.hold)
	presenter.slow_motion_requested.connect(driver.slow_motion)
	app.presentation_mount.add_child(presenter)
	var match_music: AudioStream = null
	if kits.arena != null:
		match_music = kits.arena.stream_for(PresentationKit.CUE_MUSIC)
	app.publish_match_music(match_music)
	## The router emits screen_changed after _ready. Selecting here as well
	## means the arena theme owns the loop even if that signal already ran.
	app.select_screen_music(AppScreen.Id.MATCH)
	_build_ui(config, kits)
	hud.reduced_motion = options.reduced_motion
	round_start.reduced_motion = options.reduced_motion
	if options.captions:
		presenter.audio().caption_requested.connect(hud.show_caption)
	if options.sound_captions:
		presenter.sound_caption_requested.connect(hud.show_sound_caption)
	if app.claim_set_intro():
		var takes: Array[IntroTake] = []
		for slot in 2:
			takes.append(IntroTake.of(IntroRehearsal.record(config.rules, config.seed_value, slot)))
		intro = presenter.create_intro(app.camera_rig.camera(), takes)
		intro.card_requested.connect(hud.show_card)
		intro.finished.connect(_on_intro_finished)
		_sync_clock()
	else:
		_announce_round()
	_sync_chrome()
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
	_ready_pad()


func _exit_tree() -> void:
	if Input.joy_connection_changed.is_connected(_on_pad_connection):
		Input.joy_connection_changed.disconnect(_on_pad_connection)
	human.input.cancel_all()
	if host != null:
		host.leave()
		host = null
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
	if not _user_paused:
		round_start.advance(delta)
	if not driver.paused:
		var keys := InputActions.move_vector()
		human.input.set_key_axis(keys.x, keys.y)
	var scaled := delta
	if not _finished:
		var steps := driver.consume(delta)
		scaled = driver.presentation_delta()
		for _i in steps:
			_advance_tick()
			if _finished:
				break
	presenter.render(driver.alpha(), delta, scaled)
	debug_overlay.update(presenter.current_snapshot(), Engine.get_frames_per_second())
	_sync_chrome()


## The one presentation-chrome policy (PRES-CHROME-001): the gameplay HUD —
## plates, bars, pips, clock, Pause — shows only while a duel is being fought.
## Never during the set intro, the round-start card, or the set's final beat
## and victory; no director toggles it.
func is_gameplay_chrome_visible() -> bool:
	if session == null or _finished or is_intro_playing() or is_in_final_beat():
		return false
	return session.state.phase != MatchPhase.Id.ROUND_INTRO


func _sync_chrome() -> void:
	if hud != null:
		hud.set_gameplay_chrome(is_gameplay_chrome_visible())


## Introduce the round about to start: "MATCH N" over the set score, in the
## HUD's left/right order (the human is always on the left).
func _announce_round() -> void:
	var snapshot := presenter.current_snapshot()
	if snapshot.phase != MatchPhase.Id.ROUND_INTRO:
		return
	var human_slot := session.config.human_slot
	round_start.announce_match(snapshot.round_number, PackedInt32Array([snapshot.scores[human_slot], snapshot.scores[1 - human_slot]]), snapshot.rounds_to_win)


## True once the deciding round has ended and its final beat — the rest of that
## round, played live — is playing.
func is_in_final_beat() -> bool:
	return _set_decided and not _finished


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
	_announce_round()
	_sync_chrome()


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
		## The numbers, the swing vectors, and the elbow solve are one mode.
		## Reading "closing speed 4.2" without seeing which way the tip is
		## going — or which way an elbow was asked to bend — is half the picture,
		## and splitting them across two keys only ever meant forgetting one.
		presenter.debug_vectors().visible = debug_overlay.visible
		for slot in 2:
			presenter.fighter_proxy(slot).set_pose_debug(debug_overlay.visible)
		return
	if driver.paused or _finished or event.is_echo() or not event.is_action(InputActions.ATTACK):
		return
	get_viewport().set_input_as_handled()
	var source := HumanInputState.SOURCE_KEY
	if event is InputEventMouseButton:
		source = HumanInputState.SOURCE_POINTER
	elif event is InputEventJoypadButton:
		source = HumanInputState.SOURCE_PAD
	if event.is_pressed():
		human.input.attack_down(source)
	else:
		human.input.attack_up(source)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED:
			pause()


func _ready_pad() -> void:
	if not Input.joy_connection_changed.is_connected(_on_pad_connection):
		Input.joy_connection_changed.connect(_on_pad_connection)


func _on_pad_connection(_device: int, connected: bool) -> void:
	if not connected:
		release_pad()


## A removed pad must not leave the attack held.
func release_pad() -> void:
	human.input.cancel_all()


func _advance_tick() -> void:
	var phase_before := session.state.phase
	var events := host.step() if host != null else session.step()
	var snapshot := SnapshotProjector.project(session.state, session.config.rules, debug_overlay != null and debug_overlay.visible)
	presenter.push(snapshot, events)
	hud.update(snapshot)
	if session.state.phase != phase_before:
		_on_phase_transition(phase_before, session.state.phase)
	debug_overlay.observe(events)
	if tutorial != null and tutorial.observe(session.state, events):
		_show_tutorial_step()
	if MatchPhase.is_combatant(snapshot.set_winner):
		var loser := snapshot.fighter(1 - snapshot.set_winner)
		if _horn.consider(snapshot.set_winner, loser.terminal_cause):
			presenter.play_set_horn()
	var rules := session.config.rules
	var reach := PackedFloat32Array([
		WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)),
		WeaponKinematics.strike_reach(rules.combatant(1), rules.combatant(0)),
	])
	var crowd_cue := _crowd.observe(events, session.state.scores, rules.rounds_to_win, snapshot.set_winner, rules.combat, snapshot.distance, reach)
	presenter.play_crowd(crowd_cue, snapshot.set_winner, _crowd.excitement)
	if MatchPhase.is_combatant(snapshot.set_winner) and session.config.mode == MatchConfig.Mode.QUICK_PLAY_CPU:
		## The set is decided: its deciding round plays on, live, and the
		## winner's showcase follows the match's own end (PRES-VICTORY-001).
		_set_decided = true
	if session.is_finished():
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	human.input.cancel_all()
	touch.set_enabled(false)
	app.finish_match(session)


## Flush stale input at every round-boundary phase transition so no buffered
## attack, held state, or tap history leaks across rounds (INPUT-002) — so a
## press held through "MATCH N" is discarded and the first live tick after
## "FIGHT!" starts from neutral input. A new round is announced; a round going
## live calls "FIGHT!" on that same tick.
func _on_phase_transition(from: MatchPhase.Id, to: MatchPhase.Id) -> void:
	human.input.begin_input_epoch()
	touch.reset()
	if to == MatchPhase.Id.ROUND_INTRO:
		_announce_round()
	elif from == MatchPhase.Id.ROUND_INTRO and to == MatchPhase.Id.ROUND_ACTIVE:
		round_start.fight()


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


func _build_ui(config: MatchConfig, kits: DuelKits) -> void:
	var mine := session.state.fighter(config.human_slot).side
	var labels := PackedStringArray([HudCopy.sided(AppCopy.YOU, mine), HudCopy.sided(AppCopy.opponent_label(config), DuelSide.other(mine))])
	hud = DuelHud.create(labels[0], labels[1], config.human_slot, mine)
	hud.pause_pressed.connect(pause)
	add_child(hud)
	var announcer := kits.match_loadout.announcer if kits.match_loadout != null else null
	round_start = RoundStartDirector.create(announcer, presenter.audio(), labels)
	add_child(round_start)
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
	debug_overlay.describe(session.config.rules.combatants)
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
