extends TestCase

## FULL-E2E: black-box gameplay through the shipped app. Every case boots the
## real `main.tscn`, starts from Quick Play, drives the human only through real
## input (held move actions and the dash modifier on the Input singleton, the
## attack key through `push_input`), and lets the real clock, solver, presenter,
## round flow, results, and victory showcase do the rest. Nothing sets health,
## injects a DuelEvent, or resets a round by hand.
##
## The terminal scenarios stand a scripted opponent (`ScenarioController`)
## opposite the human through the app's `compose_session` seam, on a pinned
## seed; their human input scripts were found by searching the solver, and each
## case asserts the outcome it needs as a fixture before judging presentation
## (TEST-TRUTH-001), so a tuning change that moves a scenario fails loudly
## instead of passing vacuously. The canonical case plays a whole set against
## the real CPU.
##
## Implements: /spec/invariants.md#pres-terminal-001, /spec/invariants.md#pres-victory-001, /spec/invariants.md#pres-intro-001
## See also: /docs/reference/testing.md

## The scenario searches ran on this seed (it fixes sides and spawns).
const SCENARIO_SEED := 11
## Distance at which the human's scripted attack begins (m).
const STRIKE_REACH := 1.8
## Ticks between the tap and the forward dash that run the point through.
const THRUST_DASH_DELAY := 2
## Where the lethal-thrust script taps: far enough that the dash, not the tap,
## brings the point home. Found by searching the solver at rules 24 (2.0 m,
## neighbours 1.95–2.05 m with a 2–4 tick delay); rules 25's strike reach grew
## 12 cm, and the same search shifted by that reach is a thrust kill at 2.12 m.
## Rules 31's calibrated hilt track adds 22 cm more reach: 2.34 m.
const THRUST_REACH := 2.34
const DASH_TICKS := 3
## The poke: walking in at this stick strength, tapping at reach.
const POKE_STICK := 0.4
## Walk-off: backing out at this strength drops close to the edge.
const WALK_OFF_STICK := 0.35
## Shove: the human stops this far inside the rim; the opponent dashes from
## this close. The impulse itself is BODY-PUSH's to prove; this journey only
## proves that a real dash ends in a ring-out carried by the collision.
const SHOVE_STOP_FROM_RIM := 0.3
const SHOVE_REACH := 1.05
## Real seconds after a terminal tick: past every release beat, which runs on
## presentation-scaled time and so waits out the lethal hitstop and slow motion.
const TERMINAL_SETTLE := 1.6
## The cut-down: from this close, each cut charged this many ticks — a real
## wind-up, because a blade resting on the torso it just cut cannot cut it
## again until it has left it (RIGID-CONTACT-001, COMBAT-007).
const CUT_REACH := 1.5
const CUT_CHARGE_TICKS := 24
## The COMBAT exchange (clash → pressure → slide → disengage → riposte),
## found by searching the solver against the standing guard.
const EXCHANGE_REACH := 1.8
const EXCHANGE_CHARGE_TICKS := 16
const EXCHANGE_PRESS_TICKS := 24
const EXCHANGE_SLIDE_TICKS := 20
const EXCHANGE_BACK_TO := 2.3
## The scripted attacker in the evasion and riposte journeys judges its measure
## on the distance it saw this many ticks ago (100 ms) — a human's measure, so
## spacing taken inside that lag is spacing it did not see.
const ATTACKER_LAG_TICKS := 6
## PARRY-RIPOSTE: the human winds once the attacker is this far outside reach,
## which carries its sword to the load side, into the tap's path.
const RIPOSTE_WIND_LEAD := 0.2
## BAIT: the attacker releases its full charge from this far (× strike reach),
## trusting its advance to close; the human gives ground — a back-diagonal
## dash, sword wound out of the sweep — once the charged attacker is this
## close to that distance. Found by searching the solver at rules 47 (clean
## whiffs from 1.2× to 1.5× with leads of 0.2–0.7 m).
const BAIT_RELEASE_FACTOR := 1.35
const BAIT_LEAD := 0.4


func _init() -> void:
	suite_name = "FULL-E2E"


# -- Canonical set ------------------------------------------------------------

## The whole loop against the real CPU: introduced once (wearing the resolved
## colorways), every round transition clean, the set resolved by the solver,
## the winner shown once from authority, results interactive only after it,
## the replay intact, then a Rematch that is a fresh set and a clean exit.
func test_a_full_set_against_the_cpu_resolves_showcases_and_rematches_clean() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var app := driver.app
	var difficulty := app.settings.difficulty
	assert_true(driver.press(app.current_screen(), "QUICK PLAY"), "Quick Play is on the menu")
	await await_frames(1)
	var screen := driver.match_screen()
	var first_set := app.current_set.set_id
	assert_true(screen.is_intro_playing(), "the set opens with its introduction")
	var kits := screen.presenter.duel_kits()
	for slot in 2:
		var figure := screen.intro.figure(slot)
		var combatant := kits.combatant(slot)
		var side := screen.session.state.fighter(slot).side
		assert_true(figure != screen.presenter.fighter_proxy(slot), "intro slot %d is its own figure, never the match proxy" % slot)
		assert_eq(_wears_alternate(figure, combatant), not combatant.colorway_overrides(side).is_empty(), "intro slot %d wears its resolved colorway" % slot)
	driver.key(KEY_SPACE, true)
	driver.key(KEY_SPACE, false)
	assert_false(screen.is_intro_playing(), "a press skips it")
	var session := screen.session
	var round_seen := session.state.round_number
	var transitions := 0
	var beat_before_decided := false
	var frames := 0
	while not screen.is_finished() and frames < 30000:
		_pilot(driver, session.state)
		screen.advance_frame(AppDriver.FRAME * 4.0)
		frames += 1
		if screen.is_in_final_beat() and screen.presenter.current_snapshot().set_winner == MatchPhase.NO_WINNER:
			beat_before_decided = true
		if session.state.round_number != round_seen and session.state.phase == MatchPhase.Id.ROUND_INTRO:
			round_seen = session.state.round_number
			transitions += 1
			assert_false(screen.is_intro_playing(), "round %d is never introduced" % round_seen)
			_assert_round_clean(screen, "round %d" % round_seen)
	driver.release_all()
	assert_true(screen.is_finished(), "the set resolves (%d frames)" % frames)
	assert_false(beat_before_decided, "the final beat only ever follows a decided set")
	var winner := session.state.match_winner
	assert_true(winner == 0 or winner == 1, "fixture: the set has a winner (%d)" % winner)
	assert_eq(maxi(session.state.scores[0], session.state.scores[1]), session.config.rules.rounds_to_win, "the winner reached rounds_to_win")
	assert_eq(transitions, session.state.round_number - 1, "every new round came through ROUND_INTRO")
	assert_eq(ReplayVerifier.verify(session.record, session.config.rules), ReplayVerifier.VERIFIED, "the recorded match replays to the same hash, showcase or not")
	await await_frames(1)
	var results := driver.results_screen()
	assert_true(results != null and results.is_victory(), "the decided set opens on the winner's showcase")
	var director := results.victory_director()
	var actor := director.actor()
	var winner_side := session.state.fighter(winner).side
	assert_eq(actor.side, winner_side, "the showcase is the winner, never the loser")
	var expected := app.resolve_kits(session.config).combatant(winner)
	assert_eq(actor.combatant_kit().fighter.id, expected.fighter.id, "wearing the winner's fighter")
	assert_eq(actor.combatant_kit().fighter_skin, expected.fighter_skin, "and skin")
	assert_eq(actor.combatant_kit().weapon.id, expected.weapon.id, "and weapon")
	assert_eq(_wears_alternate(actor.model(), actor.combatant_kit()), not expected.colorway_overrides(winner_side).is_empty(), "and the colorway resolved for their side")
	for child in app.presentation_mount.get_children():
		assert_false(child is MatchPresenter, "no match proxy survives into the showcase")
	assert_eq(app.claim_set_victory(), false, "the set's one showcase is spent")
	var card := results.victory_card()
	var elapsed := 0.0
	var saw_locked := false
	while results.is_victory_cinematic() and elapsed < 10.0:
		if not card.are_results_revealed() and results.actions()[0].disabled:
			saw_locked = true
		results.advance_frame(1.0 / 30.0)
		elapsed += 1.0 / 30.0
	assert_true(saw_locked, "the results are hidden and disabled while the cinematic plays")
	assert_true(elapsed >= director.profile().interactive_time - 0.05, "the full sequence plays before the results (%.2f s)" % elapsed)
	assert_true(card.are_results_revealed() and not results.actions()[0].disabled, "then the results become interactive")
	assert_eq(card.card_text(), "WOLF", "the winner's name is on the card")
	assert_eq(card.title_text(), "VICTOR", "with the title")
	assert_true(card.has_streak(), "and the final cut's streak became the divider")
	assert_eq(actor.current_clip(), director.profile().idle_clip, "Wolf settles into his victory idle")
	var victory_ref: WeakRef = weakref(director)
	assert_true(driver.press(results, "REMATCH"), "Rematch is offered")
	await await_frames(2)
	var rematch := driver.match_screen()
	assert_true(rematch != null and rematch.session != session, "a rematch composes a fresh session")
	assert_ne(app.current_set.set_id, first_set, "as a new set")
	assert_true(rematch.is_intro_playing(), "which is introduced again")
	assert_true(victory_ref.get_ref() == null or (victory_ref.get_ref() as Node).is_queued_for_deletion(), "and the showcase is gone")
	assert_eq(app.settings.difficulty, difficulty, "player settings outlive the set")
	_assert_round_clean(rematch, "the rematch")
	rematch.skip_intro()
	rematch.quit_to_menu()
	await await_frames(2)
	assert_eq(app.presentation_mount.get_child_count(), 0, "leaving for the menu leaves nothing in the world")
	driver.shutdown()
	await await_frames(2)


## Leaving from the winner's results frees the showcase and silences it.
func test_leaving_the_victory_for_the_menu_cleans_up() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	## Three straight scripted kills against a standing opponent decide the set.
	for _round in 3:
		_cut_down(driver, screen)
		driver.release_all()
		driver.run_until(screen, func() -> bool: return screen.is_finished() or screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	driver.run_until(screen, screen.is_finished)
	assert_eq(screen.session.state.match_winner, 0, "fixture: the human won the set")
	await await_frames(1)
	var results := driver.results_screen()
	assert_true(results.is_victory(), "fixture: the showcase is up")
	var director := results.victory_director()
	results.advance_frame(1.0)
	assert_true(results.is_victory_cinematic() and director.elapsed() >= 1.0, "fixture: the showcase is mid-cinematic")
	driver.key(KEY_ESCAPE, true)
	driver.key(KEY_ESCAPE, false)
	assert_false(results.is_victory_cinematic(), "Escape skips the cinematic rather than leaving mid-shot")
	assert_eq(app_screen(driver), AppScreen.Id.RESULTS, "and the press activated nothing")
	assert_true(driver.press(results, "RETURN TO MENU"), "the menu is offered once the results are up")
	await await_frames(2)
	assert_eq(app_screen(driver), AppScreen.Id.MAIN_MENU, "back at the menu")
	assert_false(is_instance_valid(director) and director.is_inside_tree(), "the showcase left the world")
	assert_eq(driver.app.presentation_mount.get_child_count(), 0, "nothing is left in the presentation mount")
	assert_true(driver.app.camera_rig.camera().current, "the gameplay camera is current again")
	driver.shutdown()
	await await_frames(2)


# -- Terminal scenarios -------------------------------------------------------

func test_a_slash_kill_cuts_down_drops_one_sword_and_resolves_the_round() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	_cut_down(driver, screen)
	driver.release_all()
	var hit := _killing_blow(screen, 1)
	assert_true(hit != null and hit.text(DuelEventKeys.CONTACT_KIND) == "slash", "fixture: the killing blow was a cut (%s)" % (hit.text(DuelEventKeys.CONTACT_KIND) if hit != null else "none"))
	assert_false(screen.session.state.fighter(1).is_alive(), "fixture: and killed")
	_settle(driver, screen)
	var victim := screen.presenter.fighter_proxy(1)
	assert_true(screen.presenter.has_death_started(1), "the victim's death plays")
	assert_true(DeathPresentationProfile.SLASH_STYLES.has(victim.death_style()) or victim.combatant_kit().fighter.death.slash_styles.has(victim.death_style()), "as a cut-down (%s)" % victim.death_style())
	assert_false(screen.presenter.fighter_proxy(0).is_finishing(), "a cut never holds the striker in a run-through")
	assert_eq(screen.presenter.dropped_weapons().size(), 1, "exactly one sword drops")
	assert_true(victim.is_weapon_dropped() and not screen.presenter.fighter_proxy(0).is_weapon_dropped(), "the victim's, not the striker's")
	assert_false(victim.has_fall_request(), "a death on the platform is not a fall")
	assert_eq(screen.session.state.end_reason, MatchPhase.REASON_KILL, "the round resolved as a kill")
	assert_eq(screen.session.state.scores, PackedInt32Array([1, 0]), "and scored")
	## Next round: every terminal latch is gone and the swords are back.
	driver.run_until(screen, func() -> bool: return screen.session.state.round_number == 2 and screen.session.state.phase == MatchPhase.Id.ROUND_INTRO)
	screen.advance_frame(AppDriver.FRAME)
	_assert_round_clean(screen, "round 2")
	driver.shutdown()
	await await_frames(2)


## POST-ROUND journey (Phases 14–16), through real input only: the winner of a
## cut-down keeps control through the post-round freedom and the result — no
## input dead zone — walks into the body and pushes it, the body is drawn where
## authority has it, nothing about the round changes, and the next round
## arrives clean.
func test_the_winner_keeps_control_and_pushes_the_body_until_the_next_round() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	_cut_down(driver, screen)
	var state := screen.session.state
	assert_false(state.fighter(1).is_alive(), "fixture: the opponent was cut down (%s)" % _tally(screen))
	assert_eq(state.phase, MatchPhase.Id.POST_ROUND_FREE, "fixture: the round is decided")
	var scores := state.scores.duplicate()
	var body := state.fighter(1)
	var me := state.fighter(0)
	var moved := {MatchPhase.Id.POST_ROUND_FREE: 0.0, MatchPhase.Id.ROUND_RESULT: 0.0}
	var body_start := Vector2.INF
	var frames := 0
	while state.round_number == 1 and frames < 600:
		var phase := state.phase
		var before := Vector2(me.x, me.y)
		## Push the body until it has clearly moved, then step sideways: a
		## winner who walked on forever would follow it off the rim.
		var pushed := body_start != Vector2.INF and Vector2(body.x, body.y).distance_to(body_start) >= 0.2
		if phase == MatchPhase.Id.POST_ROUND_FREE and not pushed:
			driver.hold_move(0.0, 1.0)
		else:
			driver.hold_move(1.0, 0.0)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
		if state.round_number != 1:
			break
		if moved.has(phase):
			moved[phase] = float(moved[phase]) + Vector2(me.x, me.y).distance_to(before)
		if phase == MatchPhase.Id.ROUND_RESULT:
			assert_false(me.is_falling, "fixture: the winner is still on the platform in the result")
		if body.fallen.is_lying() and body_start == Vector2.INF:
			body_start = Vector2(body.x, body.y)
	driver.release_all()
	assert_true(float(moved[MatchPhase.Id.POST_ROUND_FREE]) > 0.3, "the winner walks on through the post-round freedom (%.2f m)" % moved[MatchPhase.Id.POST_ROUND_FREE])
	assert_true(float(moved[MatchPhase.Id.ROUND_RESULT]) > 0.1, "and through the result — no dead zone (%.2f m)" % moved[MatchPhase.Id.ROUND_RESULT])
	assert_true(body_start != Vector2.INF, "fixture: the body came to lie")
	assert_eq(state.round_number, 2, "the next round arrives")
	assert_eq(state.scores, scores, "the push changed nothing about the score")
	screen.advance_frame(AppDriver.FRAME)
	_assert_round_clean(screen, "round 2")
	driver.shutdown()
	await await_frames(2)


## The body itself, in the same journey but stopped while it is still being
## pushed: it moves along the winner's walk and is drawn exactly where
## authority has it.
func test_a_pushed_body_is_drawn_where_authority_has_it() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	_cut_down(driver, screen)
	var state := screen.session.state
	var body := state.fighter(1)
	var me := state.fighter(0)
	assert_eq(state.phase, MatchPhase.Id.POST_ROUND_FREE, "fixture: the round is decided")
	driver.run_until(screen, func() -> bool: return body.fallen.is_lying())
	var start := Vector2(body.x, body.y)
	var frames := 0
	while state.phase != MatchPhase.Id.ROUND_INTRO and Vector2(body.x, body.y).distance_to(start) < 0.15 and frames < 400:
		driver.hold_move(0.0, 1.0)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.release_all()
	var pushed := Vector2(body.x, body.y) - start
	assert_true(pushed.length() >= 0.15, "the winner's walk pushed the body (%.3f m in %d frames)" % [pushed.length(), frames])
	var away := (start - Vector2(me.x, me.y)).normalized()
	assert_true(pushed.normalized().dot(away) > 0.3, "away from the winner")
	screen.advance_frame(AppDriver.FRAME)
	var proxy := screen.presenter.fighter_proxy(1)
	var expected := ArenaTransform.to_world(body.x, body.y, 0.0)
	assert_true(Vector2(proxy.position.x - expected.x, proxy.position.z - expected.z).length() < 0.05, "drawn where authority has it")
	assert_eq(proxy.terminal_kind(screen.presenter.current_snapshot().fighter(1)), TerminalPresentationKind.Id.FALLEN_BODY, "as a fallen body")
	driver.shutdown()
	await await_frames(2)


## COMBAT journey, through real input only, against a standing guard: a cut is
## met by the guard (clash), the human keeps pressing into it (the held
## contact pushes back, and it scrapes), slides along it, backs off until the
## swords part (the scrape lets go), then steps in and lands the riposte. The
## policy was found by searching the solver (most of the nearby settings play
## the same exchange), and every stage asserts its own fact before the next.
func test_a_clash_pressed_slid_and_disengaged_ends_in_a_riposte() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	var state := screen.session.state
	var audio := screen.presenter.audio()
	var stage := 0
	var held := -1
	var stage_ticks := 0
	var clash := -1
	var pressed := 0
	var streak := 0
	var scraped := false
	var slid := false
	var apart := -1
	var riposte: DuelEvent = null
	var frames := 0
	while state.phase == MatchPhase.Id.ROUND_ACTIVE and riposte == null and frames < 2400:
		var me := state.fighter(0)
		var distance := DuelGeometry.distance(me, state.fighter(1))
		match stage:
			0:
				if distance > EXCHANGE_REACH:
					driver.hold_move(0.0, 1.0)
				else:
					driver.hold_move(0.0, 0.0)
					if held < 0 and me.weapon.phase == CombatPhase.Id.NEUTRAL:
						held = state.tick
						driver.key(KEY_SPACE, true)
					elif held >= 0 and state.tick - held >= EXCHANGE_CHARGE_TICKS:
						driver.key(KEY_SPACE, false)
						stage = 1
			1:
				driver.hold_move(0.0, 1.0)
				stage_ticks += 1
				if stage_ticks >= EXCHANGE_PRESS_TICKS:
					stage = 2
					stage_ticks = 0
			2:
				driver.hold_move(-1.0, 0.5)
				stage_ticks += 1
				if stage_ticks >= EXCHANGE_SLIDE_TICKS:
					stage = 3
			3:
				driver.hold_move(0.0, -1.0)
				if distance >= EXCHANGE_BACK_TO and state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
					stage = 4
			_:
				if distance > EXCHANGE_REACH:
					driver.hold_move(0.0, 1.0)
				else:
					driver.hold_move(0.0, 0.0)
					if me.weapon.phase == CombatPhase.Id.NEUTRAL:
						driver.tap_attack()
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
		for event in screen.session.events:
			if event.tick != state.tick - 1:
				continue
			if event.type == DuelEventTypes.BLADE_CONTACT and clash < 0:
				clash = event.tick
			elif event.type == DuelEventTypes.BODY_HIT and event.actor == 0 and apart >= 0:
				riposte = event
		if clash >= 0 and apart < 0:
			var contact := state.blade_contact
			var pushing := false
			for i in contact.hold_count():
				pushing = pushing or contact.hold_normal[i] > 0.0
				slid = slid or contact.hold_slip[i] > 0.1
			streak = streak + 1 if pushing else 0
			pressed = maxi(pressed, streak)
			scraped = scraped or audio.is_bind_held(0)
			if stage >= 3 and contact.phase == SwordContactSet.Phase.SEPARATED:
				apart = state.tick
				assert_false(audio.is_bind_held(0), "the scrape lets go when the swords part")
	driver.key(KEY_SPACE, false)
	driver.release_all()
	assert_true(clash >= 0, "the cut is met by the guard (%s)" % _tally(screen))
	assert_true(pressed >= 6, "pressing in holds the contact under load (%d ticks)" % pressed)
	assert_true(scraped, "and the held swords scrape")
	assert_true(slid, "stepping across slides one blade along the other")
	assert_true(apart > clash, "backing off parts the swords")
	assert_true(riposte != null, "and the riposte lands (%s)" % _tally(screen))
	if riposte != null:
		assert_true(riposte.tick > apart, "after the disengage")
	driver.shutdown()
	await await_frames(2)


## PROBE-EVASION-001, through real input: an attacker walks in and taps at the
## measure it saw. The human back-dashes as it reaches that measure — before
## the release — and the tap ends in the air: no sword met, no body hit. The
## same approach with the human standing meets them, so the spacing is what
## made it miss. No counter is required; a tap is the safe probe.
func test_spacing_before_the_release_makes_a_tap_miss() -> void:
	## ARRANGE: the control — the same approach against a human who stands.
	var standing := await _probe_exchange(false)
	assert_true(int(standing["released"]) >= 0, "fixture: the attacker taps at its measure")
	assert_true(int(standing["contacts"]) > 0, "fixture: against a standing human the tap meets them (%s)" % standing)
	## PERTURB + ACT: the human gives ground before the release.
	var spaced := await _probe_exchange(true)
	## ASSERT
	assert_true(int(spaced["dashed"]) >= 0 and int(spaced["dashed"]) < int(spaced["released"]), "the back-dash came before the release (dash %d, release %d)" % [spaced["dashed"], spaced["released"]])
	assert_true(bool(spaced["whiffed"]), "the tap ends without meeting the opponent (%s)" % spaced)
	assert_eq(int(spaced["contacts"]), 0, "no sword and no body was met")


## PARRY-RIPOSTE-001, through real input: the human winds as the attacker
## comes into measure, which carries the sword into the tap's path; the tap is
## parried; the human lets the wound attack go from wherever the parry left
## both fighters, and the riposte lands. Asserts the order of facts, never a
## tick count.
func test_a_wound_guard_parries_a_tap_and_the_riposte_lands() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var released: Array[int] = [-1]
	var screen := await _scenario(driver, _lagged_tapper(reach, released))
	var state := screen.session.state
	## ARRANGE
	assert_eq(screen.session.simulation.rules.version, rules.version, "fixture: Quick Play plays the standard rules")
	## ACT
	var winding := false
	var let_go := false
	var frames := 0
	while state.phase == MatchPhase.Id.ROUND_ACTIVE and _first(screen, DuelEventTypes.BODY_HIT, -1) == null and frames < 600:
		var distance := DuelGeometry.distance(state.fighter(0), state.fighter(1))
		if not winding and distance <= reach + RIPOSTE_WIND_LEAD:
			driver.key(KEY_SPACE, true)
			winding = true
		elif winding and not let_go and _first(screen, DuelEventTypes.PARRY, 0) != null:
			driver.key(KEY_SPACE, false)
			let_go = true
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.key(KEY_SPACE, false)
	## ASSERT
	var parry := _first(screen, DuelEventTypes.PARRY, 0)
	var hit := _first(screen, DuelEventTypes.BODY_HIT, -1)
	assert_true(released[0] >= 0, "fixture: the attacker tapped (%s)" % _tally(screen))
	assert_true(parry != null and parry.target == 1, "the human's wound guard parries the tap (%s)" % _tally(screen))
	assert_true(hit != null and hit.actor == 0, "and the riposte lands (%s)" % _tally(screen))
	if parry != null and hit != null:
		assert_true(hit.tick > parry.tick, "after the parry")
	assert_true(_first(screen, DuelEventTypes.BODY_HIT, 1) == null, "the attacker never landed")
	driver.shutdown()
	await await_frames(2)


## BAIT-COMMIT-COUNTER-001, the bait, through real input: an attacker winds a
## full cut, advances holding it and lets it go from a little outside reach,
## trusting the advance to close. The human gives ground before the release —
## a back-diagonal dash, winding their own attack so the sword leaves the
## sweep — and the full cut ends in the air. (At rules 47 the counter does not
## follow: the bait needs 2.4–3.0 m of space, and the attacker's own recovery
## brings its guard back before that gap can be closed. That is the measured
## design finding; this journey proves the half the physics gives.)
func test_giving_ground_with_the_sword_wound_makes_a_full_cut_whiff() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var released: Array[int] = [-1]
	var screen := await _scenario(driver, _full_cutter(reach * BAIT_RELEASE_FACTOR, released))
	var state := screen.session.state
	## ACT
	var giving := -1
	var frames := 0
	while state.phase == MatchPhase.Id.ROUND_ACTIVE and _first(screen, DuelEventTypes.ATTACK_WHIFFED, 1) == null and _first(screen, DuelEventTypes.BODY_HIT, -1) == null and frames < 900:
		var attacker := state.fighter(1)
		var distance := DuelGeometry.distance(state.fighter(0), attacker)
		var charged := attacker.weapon.phase == CombatPhase.Id.CHARGING and attacker.weapon.charge >= 1.0
		if giving < 0 and charged and distance <= reach * BAIT_RELEASE_FACTOR + BAIT_LEAD:
			giving = state.tick
			driver.key(KEY_SPACE, true)
			driver.hold_move(-0.7, -0.7, true)
		elif giving >= 0:
			driver.hold_move(-0.7, -0.7)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.key(KEY_SPACE, false)
	driver.release_all()
	## ASSERT
	assert_true(released[0] >= 0, "fixture: the attacker let its full cut go (%s)" % _tally(screen))
	assert_true(giving >= 0 and giving < released[0], "the human gave ground before the release (step %d, release %d)" % [giving, released[0]])
	assert_true(_first(screen, DuelEventTypes.ATTACK_WHIFFED, 1) != null, "the full cut ends in the air (%s)" % _tally(screen))
	assert_eq(screen.session.events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BLADE_CONTACT).size(), 0, "the wound sword was out of the sweep")
	assert_true(_first(screen, DuelEventTypes.BODY_HIT, -1) == null, "and nobody was hit")
	driver.shutdown()
	await await_frames(2)


func test_a_lethal_thrust_runs_through_and_the_victim_dies_on_the_blade() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	_strike(driver, screen, THRUST_DASH_DELAY, true, THRUST_REACH)
	var hit := _killing_blow(screen, 1)
	assert_true(hit != null and hit.text(DuelEventKeys.CONTACT_KIND) == "thrust", "fixture: the dash drove the point through as a thrust")
	assert_false(screen.session.state.fighter(1).is_alive(), "fixture: a thrust kills")
	screen.advance_frame(AppDriver.FRAME)
	assert_true(screen.presenter.fighter_proxy(0).is_finishing(), "the striker holds the run-through")
	driver.release_all()
	_settle(driver, screen)
	var victim := screen.presenter.fighter_proxy(1)
	assert_true(DeathPresentationProfile.STAB_STYLES.has(victim.death_style()), "the victim dies of the stab (%s)" % victim.death_style())
	assert_eq(screen.presenter.dropped_weapons().size(), 1, "and drops one sword")
	assert_eq(screen.session.state.fighter(1).terminal_kind(), FighterState.Terminal.KILLED, "authority reads a kill")
	driver.shutdown()
	await await_frames(2)


## A light, uncharged hit through real play leaves no terminal presentation:
## no death, no finisher, no dropped sword. The poke/thrust/slash classification
## itself is a domain-state question (exact angle, speed, phase, burst) proven
## on the manifold in POINT; a tapped walking contact is, correctly, a light
## active-cut slash (an active cut through centre is never a poke —
## WEAPON-PATH-002), and this black-box case guards that a non-killing hit
## never fires the terminal sequence.
func test_a_light_nonlethal_hit_leaves_no_terminal_presentation() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	var started := -1
	var frames := 0
	while _first(screen, DuelEventTypes.BODY_HIT, 0) == null and frames < 900:
		var state := screen.session.state
		if started < 0 and DuelGeometry.distance(state.fighter(0), state.fighter(1)) <= STRIKE_REACH:
			started = state.tick
		if started < 0:
			driver.hold_move(0.0, 1.0)
		else:
			driver.hold_move(0.0, POKE_STICK)
			if state.tick == started:
				driver.tap_attack()
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.release_all()
	var hit := _first(screen, DuelEventTypes.BODY_HIT, 0)
	var kind := hit.text(DuelEventKeys.CONTACT_KIND) if hit != null else "none"
	assert_true(hit != null, "fixture: the walking tap connected (%s)" % kind)
	assert_true(kind == "poke" or kind == "slash", "fixture: a light non-killing contact, not a thrust (%s)" % kind)
	assert_true(screen.session.state.fighter(1).is_alive(), "fixture: and the target survived")
	_settle(driver, screen)
	assert_false(screen.presenter.has_death_started(1), "no death")
	assert_false(screen.presenter.fighter_proxy(0).is_finishing(), "no finisher")
	assert_true(screen.presenter.dropped_weapons().is_empty(), "no sword leaves a hand")
	assert_false(screen.presenter.fighter_proxy(1).is_weapon_dropped(), "the target keeps theirs")
	driver.shutdown()
	await await_frames(2)


## Backing slowly off the edge: a small outward velocity, a fall that drops
## close to the lip, and the hands letting go a beat later.
func test_a_walk_off_falls_close_to_the_edge_and_lets_go_a_beat_later() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	driver.hold_move(0.0, -WALK_OFF_STICK)
	driver.run_until(screen, func() -> bool: return _first(screen, DuelEventTypes.RING_OUT, 0) != null, 3000)
	driver.release_all()
	var fell := _first(screen, DuelEventTypes.RING_OUT, 0)
	assert_true(fell != null, "fixture: the human walked off the edge")
	var exit := Vector2(fell.number(DuelEventKeys.VELOCITY_X), fell.number(DuelEventKeys.VELOCITY_Y)).length()
	assert_true(exit > 0.0 and exit < 2.0, "fixture: at a walking pace (%.2f m/s)" % exit)
	screen.advance_frame(AppDriver.FRAME)
	var proxy := screen.presenter.fighter_proxy(0)
	assert_true(proxy.has_fall_request(), "the fall owns the root")
	assert_false(screen.presenter.has_death_started(0), "a ring-out is not a death")
	assert_true(screen.presenter.is_drop_pending(0), "the hands have not let go at the ledge")
	_settle(driver, screen)
	assert_true(screen.presenter.has_drop_released(0), "they let go a beat later")
	var edge := ArenaTransform.to_world(fell.number(DuelEventKeys.POSITION_X), fell.number(DuelEventKeys.POSITION_Y))
	var drift := Vector2(proxy.position.x - edge.x, proxy.position.z - edge.z).length()
	assert_true(drift < 1.5, "a slow step off drops close to the lip (%.2f m out)" % drift)
	assert_eq(screen.session.state.end_reason, MatchPhase.REASON_RING_OUT, "authority reads a ring-out")
	driver.shutdown()
	await await_frames(2)


## A shove off the edge by a real body collision: the exit momentum the solver
## produced carries the fall outward, harder than a walk-off.
func test_a_shove_off_the_edge_flies_out_along_the_exit_momentum() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var shove := {"close": -1}
	var opponent := ScenarioController.of(func(state: MatchState, slot: int) -> PlayerCommand:
		var me := state.fighter(slot)
		var them := state.opponent_of(slot)
		if int(shove["close"]) < 0 and DuelGeometry.distance(me, them) <= SHOVE_REACH:
			shove["close"] = state.tick
		var dashing := int(shove["close"]) >= 0 and state.tick - int(shove["close"]) < DASH_TICKS
		return PlayerCommand.create(state.tick, 0.0, 1.0, false, false, false, dashing))
	var screen := await _scenario(driver, opponent)
	var rules := screen.session.config.rules
	var frames := 0
	while _first(screen, DuelEventTypes.RING_OUT, 0) == null and frames < 3000:
		var me := screen.session.state.fighter(0)
		var stopped := rules.platform_radius - SimMath.length(me.x, me.y) <= SHOVE_STOP_FROM_RIM
		driver.hold_move(0.0, 0.0 if stopped else -1.0)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.release_all()
	var fell := _first(screen, DuelEventTypes.RING_OUT, 0)
	assert_true(fell != null, "fixture: the human went over the edge")
	## Carried by the dash's collision — body on body, or the held swords
	## meeting (a held sword carries its wielder's mass, so a dash can shove
	## through the blades as well as the torsos since rules 35). That a body
	## collision alone rings a fighter out is proven below the journey, in ROUND
	## (`test_a_pushed_fighter_loses_the_edge_where_they_cross_not_at_the_contact`).
	var collided := _first(screen, DuelEventTypes.BODY_PUSH, -1) != null or _first(screen, DuelEventTypes.BLADE_CONTACT, -1) != null
	assert_true(collided, "fixture: carried by a collision (events: %s)" % _tally(screen))
	var exit := Vector3(fell.number(DuelEventKeys.VELOCITY_X), 0.0, -fell.number(DuelEventKeys.VELOCITY_Y))
	var walk_off := rules.combatant(0).fighter.max_speed * WALK_OFF_STICK
	assert_true(exit.length() > walk_off, "fixture: the human was standing, and leaves faster than a walk-off could (%.2f > %.2f m/s)" % [exit.length(), walk_off])
	screen.advance_frame(AppDriver.FRAME)
	var proxy := screen.presenter.fighter_proxy(0)
	var start := proxy.position
	_settle(driver, screen)
	var travelled := proxy.position - start
	assert_true(Vector2(travelled.x, travelled.z).normalized().dot(Vector2(exit.x, exit.z).normalized()) > 0.95, "the fall carries on along the exit momentum")
	assert_true(travelled.y < 0.0, "while dropping")
	assert_true(screen.presenter.has_drop_released(0), "and the sword leaves the hands in the air")
	driver.shutdown()
	await await_frames(2)


## Wolf vs Wolf on default skins is a true mirror: the Dark/North copy wears
## the ALTERNATE colorway on body and weapon, the Light/South copy its own.
func test_a_mirror_match_tells_the_two_wolves_apart() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	for slot in 2:
		var proxy := screen.presenter.fighter_proxy(slot)
		var combatant := proxy.combatant_kit()
		assert_true(combatant.mirror, "fixture: slot %d is in a mirror" % slot)
		var alternate := proxy.side == DuelSide.Id.DARK_NORTH
		assert_eq(_wears_alternate(proxy.visual_root(), combatant), alternate, "slot %d body wears %s" % [slot, "ALTERNATE" if alternate else "DEFAULT"])
		if proxy.weapon_model() != null:
			assert_eq(_wears_alternate(proxy.weapon_model(), combatant), alternate, "slot %d weapon follows the fighter's colorway" % slot)
	driver.shutdown()
	await await_frames(2)


func test_a_set_is_a_match_and_claims_its_beats_once() -> void:
	var match_set := MatchSet.open(4, true, true)
	assert_eq(match_set.set_id, 4, "fixture: a set with an id")
	assert_true(match_set.claim_intro(), "its introduction is claimed once")
	assert_false(match_set.claim_intro(), "and only once")
	assert_true(match_set.claim_victory(), "its showcase is claimed once")
	assert_false(match_set.claim_victory(), "and only once")
	var practice := MatchSet.open(5, false, false)
	assert_false(practice.claim_intro() or practice.claim_victory(), "a practice set claims neither")


# -- Helpers ------------------------------------------------------------------

func app_screen(driver: AppDriver) -> AppScreen.Id:
	return driver.app.router.current_id


## Quick Play against `opponent` on the scenario seed, intro skipped, stepped
## to the first fighting tick.
func _scenario(driver: AppDriver, opponent: ScenarioController) -> MatchScreen:
	driver.app.compose_session = func(config: MatchConfig, human: HumanController, sink: TelemetrySink) -> MatchSession:
		config.seed_value = SCENARIO_SEED
		var controllers: Array[FighterController] = [human, opponent]
		return MatchSession.create(config, controllers, sink)
	driver.app.start_quick_play()
	await await_frames(1)
	var screen := driver.match_screen()
	screen.skip_intro()
	driver.run_until(screen, func() -> bool: return screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	assert_eq(screen.session.state.phase, MatchPhase.Id.ROUND_ACTIVE, "fixture: the round is live")
	return screen


## A scripted attacker that walks in and taps once, when the distance it saw
## `ATTACKER_LAG_TICKS` ago was inside `reach`; `released[0]` records the tick.
func _lagged_tapper(reach: float, released: Array[int]) -> ScenarioController:
	var seen: Array[float] = []
	return ScenarioController.of(func(state: MatchState, slot: int) -> PlayerCommand:
		if state.phase != MatchPhase.Id.ROUND_ACTIVE:
			return PlayerCommand.idle(state.tick)
		var me := state.fighter(slot)
		seen.append(DuelGeometry.distance(me, state.opponent_of(slot)))
		var perceived: float = seen[maxi(seen.size() - 1 - ATTACKER_LAG_TICKS, 0)]
		if released[0] < 0 and perceived <= reach and me.weapon.phase == CombatPhase.Id.NEUTRAL:
			released[0] = state.tick
			return PlayerCommand.create(state.tick, 0.0, 0.0, true, true)
		if released[0] < 0:
			return PlayerCommand.create(state.tick, 0.0, 1.0)
		return PlayerCommand.idle(state.tick))


## A scripted attacker that winds a full charge standing, advances holding it,
## and lets it go once inside `release_distance`; `released[0]` records the tick.
func _full_cutter(release_distance: float, released: Array[int]) -> ScenarioController:
	var pressed: Array[bool] = [false]
	return ScenarioController.of(func(state: MatchState, slot: int) -> PlayerCommand:
		if state.phase != MatchPhase.Id.ROUND_ACTIVE:
			return PlayerCommand.idle(state.tick)
		var me := state.fighter(slot)
		if not pressed[0]:
			pressed[0] = true
			return PlayerCommand.create(state.tick, 0.0, 0.0, true)
		var charged := me.weapon.charge >= 1.0
		if released[0] < 0 and charged and DuelGeometry.distance(me, state.opponent_of(slot)) <= release_distance:
			released[0] = state.tick
			return PlayerCommand.create(state.tick, 0.0, 1.0, false, true)
		return PlayerCommand.create(state.tick, 0.0, 1.0 if charged else 0.0))


## One PROBE-EVASION exchange through the app: the lagged tapper against a
## human who stands, or who back-dashes the frame the attacker reaches its
## measure. Runs until the tap resolves; returns what happened.
func _probe_exchange(dash: bool) -> Dictionary:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var released: Array[int] = [-1]
	var screen := await _scenario(driver, _lagged_tapper(reach, released))
	var state := screen.session.state
	var dashed := -1
	var frames := 0
	while state.phase == MatchPhase.Id.ROUND_ACTIVE and frames < 600 and not _resolved(screen):
		if dash and dashed < 0 and DuelGeometry.distance(state.fighter(0), state.fighter(1)) <= reach:
			dashed = state.tick
			driver.hold_move(0.0, -1.0, true)
		else:
			driver.hold_move(0.0, 0.0)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.release_all()
	var contacts := screen.session.events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BLADE_CONTACT or event.type == DuelEventTypes.BODY_HIT).size()
	var result := {"released": released[0], "dashed": dashed, "whiffed": _first(screen, DuelEventTypes.ATTACK_WHIFFED, 1) != null, "contacts": contacts}
	driver.shutdown()
	await await_frames(2)
	return result


## The attacker's tap has met something or ended in the air.
func _resolved(screen: MatchScreen) -> bool:
	return _first(screen, DuelEventTypes.ATTACK_WHIFFED, 1) != null or _first(screen, DuelEventTypes.BLADE_CONTACT, -1) != null or _first(screen, DuelEventTypes.BODY_HIT, -1) != null


## The scripted strike: walk in to reach, tap, and after `dash_delay` ticks
## dash forward for a few ticks — through real input, one tick per frame.
## Stops when the round ends, or (with `stop_on_hit`) on the first landed hit.
func _strike(driver: AppDriver, screen: MatchScreen, dash_delay: int, stop_on_hit: bool = false, reach: float = STRIKE_REACH) -> void:
	var started := -1
	var frames := 0
	var round_number := screen.session.state.round_number
	while screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE and screen.session.state.round_number == round_number and frames < 1200:
		var state := screen.session.state
		if started < 0 and DuelGeometry.distance(state.fighter(0), state.fighter(1)) <= reach:
			started = state.tick
		var age := state.tick - started
		if started < 0:
			driver.hold_move(0.0, 1.0)
		elif age == 0:
			driver.hold_move(0.0, 0.0)
			driver.tap_attack()
		elif age < dash_delay:
			driver.hold_move(0.0, 0.0)
		else:
			driver.hold_move(0.0, 1.0, age < dash_delay + DASH_TICKS)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
		if stop_on_hit and _first(screen, DuelEventTypes.BODY_HIT, 0) != null:
			return


## Cut the standing opponent down: walk in to `CUT_REACH`, and whenever the
## blade is at rest wind a short charge (`CUT_CHARGE_TICKS` held on the attack
## key) and release it — never dashing — until the round ends.
func _cut_down(driver: AppDriver, screen: MatchScreen) -> void:
	var frames := 0
	var held := -1
	var round_number := screen.session.state.round_number
	while screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE and screen.session.state.round_number == round_number and frames < 3000:
		var state := screen.session.state
		var me := state.fighter(0)
		var close := DuelGeometry.distance(me, state.fighter(1)) <= CUT_REACH
		driver.hold_move(0.0, 0.0 if close else 1.0)
		if held < 0 and close and me.weapon.phase == CombatPhase.Id.NEUTRAL:
			held = state.tick
			driver.key(KEY_SPACE, true)
		if held >= 0 and state.tick - held >= CUT_CHARGE_TICKS - 1:
			driver.key(KEY_SPACE, false)
			held = -1
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.key(KEY_SPACE, false)


## The body hit on the tick `victim` was killed, or null.
func _killing_blow(screen: MatchScreen, victim: int) -> DuelEvent:
	var killed := -1
	for event in screen.session.events:
		if event.type == DuelEventTypes.FIGHTER_KILLED and event.target == victim:
			killed = event.tick
	for event in screen.session.events:
		if event.type == DuelEventTypes.BODY_HIT and event.target == victim and event.tick == killed:
			return event
	return null


## A dumb but honest human for the CPU set: close in and tap at reach.
func _pilot(driver: AppDriver, state: MatchState) -> void:
	if state.phase != MatchPhase.Id.ROUND_ACTIVE:
		driver.hold_move(0.0, 0.0)
		return
	var close := DuelGeometry.distance(state.fighter(0), state.fighter(1)) <= STRIKE_REACH
	driver.hold_move(0.0, 0.0 if close else 1.0)
	if close and state.tick % 20 == 0:
		driver.tap_attack()


func _settle(driver: AppDriver, screen: MatchScreen) -> void:
	var frames := roundi(TERMINAL_SETTLE / AppDriver.FRAME)
	for _i in frames:
		screen.advance_frame(AppDriver.FRAME)
	driver.release_all()


## How many of each event type the session produced — what a failed scenario
## fixture reports, so a moved scenario names what happened instead.
func _tally(screen: MatchScreen) -> Dictionary:
	var counts := {}
	for event in screen.session.events:
		counts[event.type] = int(counts.get(event.type, 0)) + 1
	return counts


func _first(screen: MatchScreen, type: StringName, actor: int) -> DuelEvent:
	for event in screen.session.events:
		if event.type == type and (actor < 0 or event.actor == actor):
			return event
	return null


func _assert_round_clean(screen: MatchScreen, label: String) -> void:
	assert_true(screen.presenter.dropped_weapons().is_empty(), "%s: no sword left on the floor" % label)
	for slot in 2:
		var proxy := screen.presenter.fighter_proxy(slot)
		assert_false(screen.presenter.has_death_started(slot), "%s: slot %d has no death latched" % [label, slot])
		assert_false(screen.presenter.is_drop_pending(slot) or screen.presenter.has_drop_released(slot), "%s: slot %d has no drop latched" % [label, slot])
		assert_false(proxy.is_weapon_dropped(), "%s: slot %d holds their sword" % [label, slot])
		assert_false(proxy.has_fall_request(), "%s: slot %d is not falling" % [label, slot])
		assert_false(proxy.is_finishing(), "%s: slot %d holds no run-through" % [label, slot])


## True when any mesh under `root` wears one of the combatant's ALTERNATE
## colorway materials.
func _wears_alternate(root: Node, combatant: CombatantPresentationKit) -> bool:
	var profile := combatant.colorway()
	if root == null or profile == null:
		return false
	var alternates := profile.alternate_materials.values()
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_surface_override_material(surface)
			if material != null and alternates.has(material):
				return true
	return false
