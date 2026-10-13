class_name ResultsScreen
extends ScreenBase

## Match results (UX §25): outcome from the player's side, the score, a few
## physically meaningful stats, then Rematch (primary) or the menu.
##
## When the match resolved a set with a winner, the results open on the
## winner's showcase instead (PRES-VICTORY-001): a `VictoryDirector` on its own
## stage in the presentation mount and a `VictoryCard` over it. The results sit
## on the card's sheet and are neither visible nor enabled until the cinematic
## finishes or a deliberate press skips it — and that press never activates a
## button. A draw, a no-contest, Training, or a second visit gets the plain
## results. Leaving frees the showcase and silences it.
##
## See also: /docs/concepts/ux.md
## See also: /docs/concepts/presentation.md

var summary: MatchSummary
var _victory: VictoryDirector
var _card: VictoryCard
var _actions: Array[Button] = []


func build() -> void:
	var session := app.last_session
	if session == null:
		app.go_to(AppScreen.Id.MAIN_MENU)
		return
	summary = session.summary(session.config.human_slot)
	var winner := session.state.match_winner
	if (winner == 0 or winner == 1) and app.claim_set_victory():
		_build_victory(session, winner)
	else:
		_build_plain(session)


func _build_plain(session: MatchSession) -> void:
	var title := UiKit.title(lead, HudCopy.outcome_title(session.state.match_winner, session.config.human_slot))
	title.accessibility_live = AccessibilityServer.LIVE_POLITE
	var score := UiKit.heading(lead, AppCopy.SCORE % [summary.score_self, summary.score_opponent])
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stats(body)
	set_primary(UiKit.button(body, AppCopy.REMATCH, app.rematch, &"PrimaryButton"))
	UiKit.button(body, AppCopy.RETURN_TO_MENU, back)


func _build_victory(session: MatchSession, winner: int) -> void:
	set_frame_visible(false)
	var config := session.config
	var kits := app.resolve_kits(config)
	var options := app.presentation_options()
	var rules := config.rules
	_victory = VictoryDirector.create(
		kits.combatant(winner),
		session.state.fighter(winner).side,
		rules.combatant(winner).fighter.push_radius,
		rules.combatant(winner).weapon.hilt_radius,
		rules.combatant(winner).weapon.tip_radius,
		options.flash_scale(),
		options.particle_intensity
	)
	app.presentation_mount.add_child(_victory)
	_card = VictoryCard.create()
	_card.reduced_motion = options.reduced_motion
	add_child(_card)
	_victory.card_requested.connect(_card.show_card)
	_victory.streak_requested.connect(_card.set_streak)
	if options.captions:
		_victory.audio().caption_requested.connect(_card.show_caption)
	_victory.results_ready.connect(_on_results_ready)
	var host := _card.results_host()
	var title := UiKit.title(host, HudCopy.outcome_title(winner, config.human_slot))
	title.accessibility_live = AccessibilityServer.LIVE_POLITE
	var score := UiKit.heading(host, AppCopy.SCORE % [summary.score_self, summary.score_opponent])
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UiKit.body(host, AppCopy.RESULT_ROUNDS % summary.rounds, true)
	var rematch := UiKit.button(host, AppCopy.REMATCH, app.rematch, &"PrimaryButton")
	var menu := UiKit.button(host, AppCopy.RETURN_TO_MENU, back)
	_actions = [rematch, menu]
	for action in _actions:
		action.disabled = true
		action.focus_mode = Control.FOCUS_NONE


func _stats(host: Container) -> void:
	UiKit.body(host, AppCopy.RESULT_ROUNDS % summary.rounds, true)
	UiKit.body(host, AppCopy.RESULT_BEST % roundi(summary.best_strike), true)
	UiKit.body(host, AppCopy.RESULT_PARRIES % summary.parries, true)
	UiKit.body(host, AppCopy.RESULT_CHARGE % roundi(summary.average_charge * 100.0), true)


func _process(delta: float) -> void:
	advance_frame(delta)


## One display frame of the showcase. Tests drive it with a chosen delta.
func advance_frame(delta: float) -> void:
	if _victory != null and is_instance_valid(_victory):
		_victory.advance(delta)
	if _card != null:
		_card.advance(delta)


func is_victory() -> bool:
	return _victory != null


func is_victory_cinematic() -> bool:
	return _victory != null and is_instance_valid(_victory) and _victory.is_cinematic()


func victory_director() -> VictoryDirector:
	return _victory


func victory_card() -> VictoryCard:
	return _card


## The results actions, or none before they exist (plain results use `body`).
func actions() -> Array[Button]:
	return _actions


## Skip the showcase straight to its results. Idempotent.
func skip_victory() -> void:
	if is_victory_cinematic():
		_victory.finish()


func relayout() -> void:
	super.relayout()
	if _card != null:
		_card.layout_insets(app.safe_insets())


func _on_results_ready() -> void:
	_card.reveal_results()
	for action in _actions:
		action.disabled = false
		action.focus_mode = Control.FOCUS_ALL
	set_primary(_actions[0])
	if not DisplayServer.is_touchscreen_available():
		focus_primary.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if is_victory_cinematic() and _is_press(event):
		## Any deliberate press skips the showcase; it never reaches a button,
		## which is hidden and disabled until now.
		get_viewport().set_input_as_handled()
		skip_victory()
		return
	super._unhandled_input(event)


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return (event as InputEventKey).pressed and not event.is_echo()
	if event is InputEventMouseButton:
		return (event as InputEventMouseButton).pressed
	if event is InputEventScreenTouch:
		return (event as InputEventScreenTouch).pressed
	return false


func _exit_tree() -> void:
	if _victory != null and is_instance_valid(_victory):
		_victory.dispose()
		var parent := _victory.get_parent()
		if parent != null:
			parent.remove_child(_victory)
		_victory.queue_free()
	if app != null and app.camera_rig != null:
		app.camera_rig.camera().make_current()
