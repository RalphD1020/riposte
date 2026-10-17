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
## The scripted attacker in the evasion and line journeys judges its measure
## on the distance it saw this many ticks ago (100 ms) — a human's measure, so
## spacing taken inside that lag is spacing it did not see.
const ATTACKER_LAG_TICKS := 6
## PARRY-RIPOSTE (true blade defense) against the production Hard CPU on this
## match seed: the human stands in the settled guard and does not attack until
## its blade has arrested a CPU cut, then walks in tapping. Tapping on sight
## made the human the attacker (the only parry was the CPU's). Replayed through
## the app on rules 55: the arrest is blade on blade. The recovering blade may
## still enter the torso; the human's later attack is the answer.
const DEFENSE_SEED := 8
## BAIT: the attacker releases its full charge from this far (× strike reach),
## trusting its advance to close; the human gives ground — a back-diagonal
## dash, sword wound out of the sweep — once the charged attacker is this
## close to that distance. Found by searching the solver at rules 47 (clean
## whiffs from 1.2× to 1.5× with leads of 0.2–0.7 m).
## The line journeys: the human reads the incoming tap this far outside reach
## (m) and walks behind or into the blade for this many ticks.
const LINE_READ_LEAD := 0.5
const LINE_WALK_TICKS := 12
const BAIT_RELEASE_FACTOR := 1.35
const BAIT_LEAD := 0.4
## TORSO-CIRCLE-001: approaching at an angle and tapping from here used to
## reach the standing opponent's grip before any steel. Hands and the handle
## are not a target, so the same trace misses the torso.
const GRIP_STICK := Vector2(-0.7, 1.0)
const GRIP_REACH := 2.3
## CLEAN-STRIKE: a charged cut from here meets no steel at all.
const CLEAN_REACH := 1.8
const CLEAN_CHARGE_TICKS := 24
## Advancing vs planted: the same tap released at this distance.
const VELOCITY_REACH := 1.8


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


## The set-winning sequence through the real match: the deciding round keeps
## playing with the gameplay HUD down, then the showcase pushes in and its
## fanfare sounds once.
func test_the_deciding_round_hides_the_hud_and_the_fanfare_plays_once() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	var beat := {"hid": false}
	for _round in screen.session.config.rules.rounds_to_win:
		if screen.is_finished():
			break
		assert_true(screen.hud.is_gameplay_chrome_visible(), "fixture: a live round shows the HUD")
		_cut_down(driver, screen)
		driver.release_all()
		driver.run_until(screen, func() -> bool:
			if screen.is_in_final_beat() and not screen.hud.is_gameplay_chrome_visible():
				beat["hid"] = true
			return screen.is_finished() or screen.session.state.phase == MatchPhase.Id.ROUND_ACTIVE)
	assert_eq(screen.session.state.match_winner, 0, "fixture: the human won the set")
	var kills := 0
	for event in screen.session.events:
		if event.type == DuelEventTypes.FIGHTER_KILLED and event.target == 1:
			kills += 1
	assert_true(kills >= 1, "the set contains a kill, not a manufactured ending (%d)" % kills)
	assert_true(bool(beat["hid"]), "the deciding round hides the gameplay HUD while it is still being played")
	await await_frames(1)
	var results := driver.results_screen()
	var director := results.victory_director()
	var profile := director.profile()
	assert_true(results.is_victory() and profile.fanfare != null, "fixture: the winner's showcase has a fanfare")
	assert_eq(_sting_count(director, profile.fanfare), 0, "fixture: it has not played on entry")
	assert_near(director.camera().fov, profile.fov_start, 0.5, "the camera opens on the full figure")
	var elapsed := 0.0
	while results.is_victory_cinematic() and elapsed < 10.0:
		results.advance_frame(AppDriver.FRAME)
		elapsed += AppDriver.FRAME
	assert_false(results.is_victory_cinematic(), "the showcase reaches the results")
	assert_eq(_sting_count(director, profile.fanfare), 1, "the fanfare played once, on the lock")
	assert_near(director.camera().fov, profile.fov_finish, 0.05, "and the camera has pushed in")
	results.advance_frame(2.0)
	assert_eq(_sting_count(director, profile.fanfare), 1, "sitting on the results does not play it again")
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
	assert_eq(state.fighter(0).stamina, 1.0, "round 2 starts the winner at full stamina")
	assert_eq(state.fighter(1).stamina, 1.0, "and the opponent")
	assert_near(screen.hud.stamina_bar(0).value, 1.0, 1.0e-6, "the HUD shows that reset")
	assert_near(screen.hud.stamina_bar(1).value, 1.0, 1.0e-6, "on both plates")
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


## PARRY-RIPOSTE-001 (true steel defense), through real input against the
## production Hard CPU on `DEFENSE_SEED`: the human stands in the settled
## guard and does not attack. The CPU's released cut meets the human's blade
## and is physically arrested: it leaves the swinging phases on that tick, and
## that is the parry. Tapping on sight (the previous policy) made the human
## the attacker, so the only parry was the CPU's. In this trace the steel is
## blade on blade (`PAIR_BLADES`); the crossguard's protected side stays the
## GRIP suite's witness. In this trace the cut wounded nothing before the
## arrest. Arrest ends the swing; the recovering blade may still enter the
## torso on the path that arrest left (COMBAT-010, rules 55). Any such touch
## is a residual of this same swing (PARRY-001): before the CPU's next
## release, while that blade is in recovery. It has to be the torso. A slash
## or a graze has to agree with `graze_quality` and read below a solid hit.
## A poke has to meet the existing tip gates and stay under `poke_lethal_quality`.
## Either way the damage is `damage_for` of that quality. A thrust, which the
## lethality law kills outright, does not pass. None of this is a fraction of
## health, and none of it is a new damage category. It is not the answer. The
## human then walks in tapping and its ordinary attack, released after the
## parry, lands on the CPU for more than any such residual. No immunity timer
## is asserted, and the observed graze is not pinned. No "first" is claimed
## (COMBAT-010). Only the order of facts is asserted, never a tick; the
## parry's physics are CONTACT's to prove.
func test_a_blade_catch_parries_a_cpu_attack_and_the_riposte_lands() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var cpu := CpuController.create(rules, CpuProfile.hard(), DEFENSE_SEED, 1)
	var screen := await _scenario(driver, cpu, DEFENSE_SEED)
	var state := screen.session.state
	## ARRANGE
	assert_eq(screen.session.simulation.rules.version, rules.version, "fixture: Quick Play plays the standard rules")
	## ACT
	var parry: DuelEvent = null
	var riposte: DuelEvent = null
	var seen := 0
	var frames := 0
	var health_before := 0.0
	var swinging_at_parry := true
	var residual := 0.0
	var recovering: Array[int] = []
	while state.phase == MatchPhase.Id.ROUND_ACTIVE and riposte == null and frames < 1500:
		var me := state.fighter(0)
		var distance := DuelGeometry.distance(me, state.fighter(1))
		driver.hold_move(0.0, 1.0 if parry != null and distance > reach else 0.0)
		if parry != null and me.weapon.phase == CombatPhase.Id.NEUTRAL and distance <= reach:
			driver.tap_attack()
		health_before = state.fighter(1).health
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
		while seen < screen.session.events.size():
			var event: DuelEvent = screen.session.events[seen]
			seen += 1
			if parry == null and event.type == DuelEventTypes.PARRY and event.actor == 0:
				parry = event
				swinging_at_parry = CombatPhase.is_swinging(state.fighter(1).weapon.phase)
			elif parry != null and riposte == null and event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
				riposte = event
		if parry != null and state.fighter(1).weapon.phase == CombatPhase.Id.RECOVERY:
			recovering.append(state.tick - 1)
	driver.release_all()
	## ASSERT
	assert_true(parry != null, "the human's blade parries a CPU attack (%s)" % _tally(screen))
	if parry != null:
		assert_eq(parry.target, 1, "the parried attack is the CPU's")
		var released := _last_before(screen, DuelEventTypes.ATTACK_RELEASED, 1, parry.tick)
		assert_true(released != null, "and it was an attack the CPU really released")
		var clash := _blade_contact_at(screen, parry.tick)
		assert_true(clash != null and bool(clash.data[DuelEventKeys.ARRESTED_1]), "steel met the cut and the CPU's cut was arrested there")
		if clash != null:
			assert_true(clash.number(DuelEventKeys.IMPULSE) > 0.0, "the arrest is a solved, positive impulse")
			assert_eq(int(clash.data[DuelEventKeys.STEEL_PAIR]), SwordContactSet.PAIR_BLADES, "fixture: in this trace the steel is blade on blade")
		assert_false(swinging_at_parry, "the arrest stopped the cut: it left the swinging phases")
		## The arrested swing is the CPU's until its next release: a later
		## attack's recovery is that attack's, not the parried one's.
		var next_release := _first_after(screen, DuelEventTypes.ATTACK_RELEASED, 1, parry.tick)
		var swing_ends := next_release.tick if next_release != null else state.tick
		var after := screen.session.events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BODY_HIT and event.actor == 1 and event.tick > parry.tick and event.tick < swing_ends and recovering.has(event.tick))
		for wound: DuelEvent in after:
			residual += wound.number(DuelEventKeys.DAMAGE)
			assert_eq(wound.text(DuelEventKeys.REGION), DuelEventKeys.REGION_TORSO, "a residual touch is the torso (tick %d)" % wound.tick)
			var kind := wound.text(DuelEventKeys.CONTACT_KIND)
			assert_ne(kind, "thrust", "a thrust that still qualifies is a lethal run-through, not a residual")
			assert_false(bool(wound.data[DuelEventKeys.LETHAL]), "the residual is not a lethal entry")
			var quality := wound.number(DuelEventKeys.QUALITY)
			assert_true(wound.number(DuelEventKeys.DAMAGE) > 0.0, "the residual is a real entry")
			assert_near(wound.number(DuelEventKeys.DAMAGE), rules.combat.damage_for(quality), 1.0e-6, "damage is the existing curve at quality %.4f" % quality)
			assert_near(quality, wound.number(DuelEventKeys.PHYSICAL_QUALITY), 1.0e-9, "exposure does not scale this entry")
			if kind == "poke":
				var weapon := rules.combatant(1).weapon
				assert_true(wound.number(DuelEventKeys.BLADE_FRACTION) >= weapon.tip_region_start, "a poke is the tip (%.3f)" % wound.number(DuelEventKeys.BLADE_FRACTION))
				assert_true(wound.number(DuelEventKeys.THRUST_ALIGNMENT) >= rules.combat.point_strike_alignment, "and it is aligned enough to be a point strike")
				assert_true(wound.number(DuelEventKeys.INCIDENCE_QUALITY) >= rules.combat.point_strike_incidence, "and it meets the point squarely enough")
				assert_true(quality < rules.combat.poke_lethal_quality, "the poke stays under the existing lethal line (%.3f)" % quality)
			else:
				var glancing := wound.number(DuelEventKeys.CONTACT_QUALITY) < rules.combat.graze_quality
				assert_eq(kind, "graze" if glancing else "slash", "the kind is the existing geometry classification")
				assert_true(quality < SwingSemantics.GRADE_SOLID, "a cut residual reads below a solid hit (%.3f)" % quality)
		if released != null:
			var before := screen.session.events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BODY_HIT and event.actor == 1 and event.tick >= released.tick and event.tick <= parry.tick)
			assert_eq(before.size(), 0, "fixture: in this trace the cut wounded nothing before it was arrested")
			## Within the tick the solver resolves contacts in time order and
			## appends them as it goes: the parry is read after the arrest.
			var events := screen.session.events
			if clash != null:
				assert_true(events.find(clash) < events.find(parry), "the parry is the reading of that arrest")
	assert_true(riposte != null, "the human's answer lands (%s)" % _tally(screen))
	if riposte != null and parry != null:
		var answer := _last_before(screen, DuelEventTypes.ATTACK_RELEASED, 0, riposte.tick + 1)
		assert_true(answer != null and answer.tick > parry.tick, "from an attack released after the parry")
		assert_true(state.fighter(1).health < health_before, "and it is in the CPU's health (%.2f -> %.2f)" % [health_before, state.fighter(1).health])
		assert_true(riposte.number(DuelEventKeys.DAMAGE) > residual, "and it outweighs any residual of the arrested swing (%.2f > %.2f)" % [riposte.number(DuelEventKeys.DAMAGE), residual])
	driver.shutdown()
	await await_frames(2)


## LINE-CHANGE-001, through real input, in this one scene (the scenario seed,
## the lagged tapper): the human reads the tap coming and steps toward the
## cut's origin side before it is released. Here (rules 52) that line change
## puts the human's blade across the root of the cut: the cutter's own
## crossguard meets it from its blade side — real steel, solved, but it does
## not arrest the cut — and the tap carries on to the torso of that same
## attack. A hand or the handle in the way is not a wound. A scenario trace,
## not a rule about every origin-side step. That a line change can be
## capitalized on is LINE-CHANGE-CAPITALIZATION-001, which is OPEN; nothing
## here claims the human wins the exchange.
func test_an_origin_side_step_here_meets_the_cuts_crossguard_first() -> void:
	## ARRANGE + ACT
	var journey := await _line_journey("origin")
	## ASSERT
	_assert_line_fixture(journey)
	var events: Array[DuelEvent] = journey["events"]
	var wounds := events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BODY_HIT)
	var steel := events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BLADE_CONTACT)
	assert_true(wounds.size() >= 1 and steel.size() >= 1, "fixture: the tap meets steel and wounds the torso (%s)" % journey["tally"])
	if wounds.size() >= 1 and steel.size() >= 1:
		var clash: DuelEvent = steel[0]
		var first: DuelEvent = wounds[0]
		assert_true(clash.actor == 1 and clash.tick < first.tick, "the cut meets steel first")
		assert_eq(int(clash.data[DuelEventKeys.STEEL_PAIR]), SwordContactSet.PAIR_BLADE_ON_GUARD, "the cutter's own crossguard on the human's blade")
		assert_false(bool(clash.data[DuelEventKeys.ARRESTED_1]), "which does not arrest the cut")
		assert_true(first.actor == 1 and first.text(DuelEventKeys.REGION) == DuelEventKeys.REGION_TORSO, "carrying on, the tap reaches the human's torso")
		assert_eq(_count_before(events, DuelEventTypes.ATTACK_RELEASED, first.tick + 1, 1), 1, "all of it one attack")


## LINE-CHANGE-001, the same read stepped toward the cut's end side, in the same
## scene: the tap meets no steel and wounds the human's torso. The side taken
## changes what the cut meets; neither side here yields a counter.
func test_an_end_side_step_here_is_struck_on_the_torso() -> void:
	## ARRANGE + ACT
	var journey := await _line_journey("end")
	## ASSERT
	_assert_line_fixture(journey)
	var events: Array[DuelEvent] = journey["events"]
	var wounds := events.filter(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BODY_HIT)
	assert_true(wounds.size() >= 1, "fixture: the tap lands (%s)" % journey["tally"])
	if wounds.size() >= 1:
		var first: DuelEvent = wounds[0]
		assert_true(first.actor == 1 and first.text(DuelEventKeys.REGION) == DuelEventKeys.REGION_TORSO, "the tap's first wound is the human's torso (%s)" % first.text(DuelEventKeys.REGION))
		assert_eq(_count_before(events, DuelEventTypes.BLADE_CONTACT, first.tick + 1), 0, "with no steel met first")


## Both line journeys: the tap was released, the human's step started before
## it, and the wound is in the human's health.
func _assert_line_fixture(journey: Dictionary) -> void:
	assert_true(int(journey["released"]) >= 0, "fixture: the attacker tapped (%s)" % journey["tally"])
	assert_true(int(journey["step_from"]) >= 0 and int(journey["step_from"]) < int(journey["released"]), "the human stepped before the release (step %d, release %d)" % [journey["step_from"], journey["released"]])
	assert_true(float(journey["health"]) < float(journey["max_health"]), "the wound is in the human's health")


func _count_before(events: Array[DuelEvent], type: StringName, tick: int, actor: int = -1) -> int:
	return events.filter(func(event: DuelEvent) -> bool: return event.type == type and event.tick < tick and (actor < 0 or event.actor == actor)).size()


## The line journey: the opponent (slot 1) walks in and taps once when the
## distance it saw `ATTACKER_LAG_TICKS` ago is inside reach, then is a Hard
## CPU; the human (slot 0, real input) walks toward the cut's `side`
## ("origin" or "end", `CutGeometry`) for `LINE_WALK_TICKS` from the frame the
## distance is inside reach + `LINE_READ_LEAD`, then walks in tapping whenever
## its sword is free after steel. Runs until the first torso wound.
func _line_journey(side: String) -> Dictionary:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var released: Array[int] = [-1]
	var cpu := CpuController.create(rules, CpuProfile.hard(), SCENARIO_SEED, 1)
	var tapper := _lagged_tapper(reach, released)
	var opponent := ScenarioController.of(func(live: MatchState, slot: int) -> PlayerCommand:
		var cutter := live.fighter(slot)
		var tap_over := released[0] >= 0 and live.tick > released[0] and cutter.weapon.phase != CombatPhase.Id.LAUNCH and not CombatPhase.is_swinging(cutter.weapon.phase)
		return cpu.command_for(live, slot) if tap_over else tapper.command_for(live, slot))
	var screen := await _scenario(driver, opponent)
	var state := screen.session.state
	var step_from := -1
	var direction := Vector2.ZERO
	var frames := 0
	var torso := func() -> bool:
		return screen.session.events.any(func(event: DuelEvent) -> bool: return event.type == DuelEventTypes.BODY_HIT and event.text(DuelEventKeys.REGION) == DuelEventKeys.REGION_TORSO)
	while state.phase == MatchPhase.Id.ROUND_ACTIVE and not torso.call() and frames < 900:
		var me := state.fighter(0)
		var them := state.fighter(1)
		if step_from < 0 and DuelGeometry.distance(me, them) <= reach + LINE_READ_LEAD:
			step_from = state.tick
			direction = CutGeometry.origin_side(them) if side == "origin" else CutGeometry.end_side(them)
		var touched := _first(screen, DuelEventTypes.BLADE_CONTACT, -1) != null
		if step_from >= 0 and state.tick < step_from + LINE_WALK_TICKS:
			var step := CutGeometry.step_intent(me, them, direction)
			driver.hold_move(step.x, step.y)
		elif step_from >= 0 and touched:
			driver.hold_move(0.0, 1.0)
			if me.weapon.phase == CombatPhase.Id.NEUTRAL:
				driver.tap_attack()
		else:
			driver.hold_move(0.0, 0.0)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	driver.release_all()
	var journey := {
		"released": released[0],
		"step_from": step_from,
		"events": screen.session.events.duplicate(),
		"tally": _tally(screen),
		"health": state.fighter(0).health,
		"max_health": rules.combatant(0).fighter.max_health,
	}
	driver.shutdown()
	await await_frames(2)
	return journey


## MEASURE-WHIFF-001, through real input — a whiff by *measure*, not by line
## (LINE-CHANGE-001 owns the line): an attacker winds a full cut, advances
## holding it and lets it go from a little outside reach, trusting the advance
## to close. The human gives ground before the release — a back-diagonal dash,
## winding their own attack so the sword leaves the sweep — and the full cut
## ends in the air, the distance having grown beyond reach. No counter is
## claimed: by the time that gap can be closed, the attacker's recovery has
## brought its guard back.
func test_retreating_back_and_across_out_of_measure_makes_a_full_cut_miss() -> void:
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


## TORSO-CIRCLE-001, through real input. The tap is sampled while the blade
## is swinging: it must cross a former hand disc or the handle, and it must
## stay outside the torso circle. A miss that also misses the hands does not
## prove the rule. Arms have no capsule; the hand disc is the kinematic
## stand-in.
func test_a_tap_through_the_hands_misses_when_it_misses_the_torso() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var screen := await _scenario(driver, ScenarioController.standing())
	var health_before := rules.combatant(1).fighter.max_health
	var nearest := [INF]
	var crossed := [false]
	var entered := [false]
	## ACT
	_cut_at(driver, screen, GRIP_REACH, 0, GRIP_STICK, Vector2.ZERO, func(live: MatchState) -> void:
		if not CombatPhase.is_swinging(live.fighter(0).weapon.phase):
			return
		var gap := _former_grip_gap(live, rules)
		nearest[0] = minf(nearest[0], gap)
		if gap < 0.0:
			crossed[0] = true
		if _live_torso_gap(live, rules) <= 0.0:
			entered[0] = true
	)
	## ASSERT
	assert_true(crossed[0], "the swinging blade crosses a hand or the handle (nearest gap %.3f m)" % nearest[0])
	assert_false(entered[0], "and that path stays outside the torso circle")
	var wound := _first(screen, DuelEventTypes.BODY_HIT, 0)
	assert_true(wound == null, "so the tap wounds nothing (%s)" % _tally(screen))
	assert_eq(screen.session.state.fighter(1).health, health_before, "and the victim's health is unchanged")
	assert_true(screen.session.state.fighter(1).is_alive(), "and the fight goes on")
	driver.shutdown()
	await await_frames(2)


## CLEAN-STRIKE-LETHALITY, through real input: a charged cut into a standing
## opponent meets no steel and lands square on the torso. A clean fast cut is
## decisive (rules 49): it takes at least half the victim's health.
func test_a_clean_charged_cut_is_decisive() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	## ACT
	_cut_at(driver, screen, CLEAN_REACH, CLEAN_CHARGE_TICKS, Vector2(0.0, 1.0), Vector2.ZERO)
	## ASSERT
	var hit := _first(screen, DuelEventTypes.BODY_HIT, 0)
	assert_true(hit != null, "fixture: the cut landed (%s)" % _tally(screen))
	assert_true(_first(screen, DuelEventTypes.BLADE_CONTACT, -1) == null, "fixture: no steel was met")
	if hit != null:
		assert_eq(hit.text(DuelEventKeys.REGION), DuelEventKeys.REGION_TORSO, "on the torso")
		assert_eq(hit.text(DuelEventKeys.CONTACT_KIND), "slash", "edge first")
		var health := StandardDuelRules.create().combatant(1).fighter.max_health
		assert_true(hit.number(DuelEventKeys.DAMAGE) >= health * 0.5, "and decisive (%.1f of %.0f)" % [hit.number(DuelEventKeys.DAMAGE), health])
	driver.shutdown()
	await await_frames(2)


## PHYS-001 / COMMITMENT-001, through real input: the same tap released at the
## same distance, once walking in and once planted. The body's own velocity is
## in the blade's: the advancing cut delivers more energy, with no movement
## bonus anywhere. (Backing off is not the mirror of this — it changes where on
## the blade the contact lands, so DAMAGE owns that controlled comparison.)
func test_advancing_into_the_same_tap_delivers_more_than_standing() -> void:
	var strikes: Array[DuelEvent] = []
	for advancing: bool in [true, false]:
		var driver := AppDriver.boot(7)
		await await_frames(1)
		var screen := await _scenario(driver, ScenarioController.standing())
		## ACT: walk in; planted, stop and settle before the tap.
		var state := screen.session.state
		var tapped := false
		var frames := 0
		while state.phase == MatchPhase.Id.ROUND_ACTIVE and _first(screen, DuelEventTypes.BODY_HIT, 0) == null and frames < 900:
			var me := state.fighter(0)
			var close := DuelGeometry.distance(me, state.fighter(1)) <= VELOCITY_REACH
			if advancing:
				driver.hold_move(0.0, 1.0)
				if close and not tapped:
					driver.tap_attack()
					tapped = true
			elif not close and not tapped:
				driver.hold_move(0.0, 1.0)
			else:
				driver.hold_move(0.0, 0.0)
				if not tapped and SimMath.length(me.vx, me.vy) <= 0.02:
					driver.tap_attack()
					tapped = true
			screen.advance_frame(AppDriver.FRAME)
			frames += 1
		driver.release_all()
		strikes.append(_first(screen, DuelEventTypes.BODY_HIT, 0))
		driver.shutdown()
		await await_frames(2)
	## ASSERT
	assert_true(strikes[0] != null and strikes[1] != null, "fixture: both taps land")
	if strikes[0] != null and strikes[1] != null:
		assert_eq(strikes[0].text(DuelEventKeys.REGION), DuelEventKeys.REGION_TORSO, "fixture: walking in, on the torso")
		assert_eq(strikes[1].text(DuelEventKeys.REGION), DuelEventKeys.REGION_TORSO, "fixture: planted, on the torso")
		assert_true(strikes[0].number(DuelEventKeys.SEVERITY) > strikes[1].number(DuelEventKeys.SEVERITY), "walking in delivers more energy (%.1f J > %.1f J)" % [strikes[0].number(DuelEventKeys.SEVERITY), strikes[1].number(DuelEventKeys.SEVERITY)])


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


## STAMINA-004 through the live HUD. A real dash spends stamina, standing
## still recovers it, and the bar on the human's plate matches the settled
## value both times. The next round's reset is the winner-control journey.
func test_the_stamina_bar_tracks_a_dash_and_its_recovery() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var screen := await _scenario(driver, ScenarioController.standing())
	var bar := screen.hud.stamina_bar(0)
	var me := screen.session.state.fighter(0)
	assert_true(screen.hud.is_gameplay_chrome_visible(), "fixture: the live round shows the HUD")
	assert_near(bar.value, 1.0, 1.0e-6, "fixture: the bar starts full")
	assert_near(bar.value, me.stamina, 1.0e-6, "fixture: and it matches authority")
	var before := me.stamina
	driver.hold_move(0.0, -1.0, true)
	var frames := 0
	while me.stamina >= before and frames < 120:
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	var spent := me.stamina
	var cost := screen.session.config.rules.combat.stamina_dash_cost
	assert_true(spent < before, "a dash spends stamina (%.3f -> %.3f in %d frames)" % [before, spent, frames])
	assert_true(before - spent + 1.0e-6 >= cost, "the drop is at least one dash (%.3f, cost %.2f)" % [before - spent, cost])
	assert_near(bar.value, spent, 1.0e-6, "the bar matches the spent value")
	driver.release_all()
	var resting := spent
	frames = 0
	while me.stamina <= resting + 0.01 and frames < 400:
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
	var recovered := me.stamina
	assert_true(recovered > resting, "standing still recovers stamina (%.3f -> %.3f)" % [resting, recovered])
	assert_near(bar.value, recovered, 1.0e-6, "the bar matches the recovery")
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


## Quick Play against `opponent` on `seed_value`, intro skipped, stepped to
## the first fighting tick.
func _scenario(driver: AppDriver, opponent: FighterController, seed_value: int = SCENARIO_SEED) -> MatchScreen:
	driver.app.compose_session = func(config: MatchConfig, human: HumanController, sink: TelemetrySink) -> MatchSession:
		config.seed_value = seed_value
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


## Surface gap from `pose`'s blade to a disc. Negative means the blade has entered it.
func _blade_disc_gap(pose: BladePose, weapon: WeaponDefinition, point: Vector2, disc: float) -> float:
	var hx := pose.point_x(weapon.blade_base_radius)
	var hy := pose.point_y(weapon.blade_base_radius)
	var tx := pose.point_x(weapon.tip_radius)
	var ty := pose.point_y(weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, point.x, point.y)
	return Vector2(point.x - lerpf(hx, tx, t), point.y - lerpf(hy, ty, t)).length() - disc - weapon.blade_radius


## The swinging blade's nearest gap to the standing fighter's hands or handle.
## Presentation geometry, measured so the journey can prove it crossed them.
func _former_grip_gap(state: MatchState, rules: DuelRules) -> float:
	var attacker := state.fighter(0)
	var defender := state.fighter(1)
	var spec_a := rules.combatant(0)
	var spec_d := rules.combatant(1)
	var pose := WeaponKinematics.pose_at(attacker.x, attacker.y, attacker.facing, attacker.weapon.angle, spec_a, BladePose.new())
	var theirs := WeaponKinematics.pose_at(defender.x, defender.y, defender.facing, defender.weapon.angle, spec_d, BladePose.new())
	var weapon := spec_d.weapon
	var along := PackedFloat64Array([weapon.offhand_grip_radius, weapon.dominant_grip_radius, (weapon.offhand_grip_radius + weapon.dominant_grip_radius) * 0.5])
	var radii := PackedFloat64Array([spec_d.fighter.hand_radius, spec_d.fighter.hand_radius, weapon.handle_radius])
	var least := INF
	for i in 3:
		least = minf(least, _blade_disc_gap(pose, spec_a.weapon, Vector2(theirs.point_x(along[i]), theirs.point_y(along[i])), radii[i]))
	return least


## The swinging blade's gap to the standing fighter's torso circle.
func _live_torso_gap(state: MatchState, rules: DuelRules) -> float:
	var attacker := state.fighter(0)
	var defender := state.fighter(1)
	var spec_a := rules.combatant(0)
	var pose := WeaponKinematics.pose_at(attacker.x, attacker.y, attacker.facing, attacker.weapon.angle, spec_a, BladePose.new())
	return _blade_disc_gap(pose, spec_a.weapon, Vector2(defender.x, defender.y), rules.combatant(1).fighter.hurt_radius)


## The human walks in at `approach` until within `reach`, then presses the
## attack — released the same frame (`charge` 0, a tap) or `charge` frames
## later — holding `after` from the press; runs until the human lands a body
## hit and 40 frames more, or the round ends.
func _cut_at(driver: AppDriver, screen: MatchScreen, reach: float, charge: int, approach: Vector2, after: Vector2, watch: Callable = Callable()) -> void:
	var state := screen.session.state
	var pressed := -1
	var frames := 0
	var landed := -1
	while state.phase == MatchPhase.Id.ROUND_ACTIVE and frames < 1200 and (landed < 0 or frames - landed < 40):
		if pressed < 0 and DuelGeometry.distance(state.fighter(0), state.fighter(1)) > reach:
			driver.hold_move(approach.x, approach.y)
		elif pressed < 0:
			pressed = frames
			driver.hold_move(after.x, after.y)
			if charge == 0:
				driver.tap_attack()
			else:
				driver.key(KEY_SPACE, true)
		else:
			driver.hold_move(after.x, after.y)
			if charge > 0 and frames - pressed == charge:
				driver.key(KEY_SPACE, false)
		screen.advance_frame(AppDriver.FRAME)
		frames += 1
		if watch.is_valid():
			watch.call(state)
		if landed < 0 and _first(screen, DuelEventTypes.BODY_HIT, 0) != null:
			landed = frames
		if pressed >= 0 and landed < 0 and frames - pressed > charge + 120:
			break
	driver.key(KEY_SPACE, false)
	driver.release_all()


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


## The last `type` event by `actor` strictly before `tick`, or null. An
## attack's authoritative boundary is its ATTACK_RELEASED: a fighter cannot
## release another until the last has ended.
func _first_after(screen: MatchScreen, type: StringName, actor: int, tick: int) -> DuelEvent:
	for event in screen.session.events:
		if event.tick > tick and event.type == type and event.actor == actor:
			return event
	return null


func _last_before(screen: MatchScreen, type: StringName, actor: int, tick: int) -> DuelEvent:
	var found: DuelEvent = null
	for event in screen.session.events:
		if event.tick >= tick:
			break
		if event.type == type and event.actor == actor:
			found = event
	return found


## The blade contact resolved on `tick`, or null.
func _blade_contact_at(screen: MatchScreen, tick: int) -> DuelEvent:
	for event in screen.session.events:
		if event.type == DuelEventTypes.BLADE_CONTACT and event.tick == tick:
			return event
	return null


func _sting_count(director: VictoryDirector, stream: AudioStream) -> int:
	var count := 0
	for played in director.audio().history:
		if played == stream:
			count += 1
	return count


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


## Advance the shipped screen until the simulation has stepped one tick (a
## hitstop holds the clock for some frames; ticks are what count).
func _advance_tick(screen: MatchScreen) -> void:
	var tick := screen.session.state.tick
	for _frame in 120:
		screen.advance_frame(AppDriver.FRAME)
		if screen.session.state.tick != tick:
			return


## BIND-DISENGAGE-001 through real input (BLADE-ESCAPE-001,
## BLADE-CONTACT-RELEASE-001), from a named starting scenario: once the round
## is live the two fighters are stood with crossed diagonal guards 5 mm apart.
## The human and the scripted opponent walk in until the solver forms a
## contact. The human then backs off and the steel physically parts, and
## walks back in until it meets the opponent again. Idle persistence of a
## resting overlap is the domain suite's contract, not this journey. Nothing
## here says who wins.
func test_a_bind_is_formed_held_released_and_re_engaged_through_real_input() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var reach := WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1))
	var walk_until := [-1]
	var opponent := ScenarioController.of(func(live: MatchState, _slot: int) -> PlayerCommand:
		return PlayerCommand.create(live.tick, 0.0, 1.0) if live.tick < walk_until[0] else PlayerCommand.idle(live.tick))
	var screen := await _scenario(driver, opponent)
	var state := screen.session.state
	## ARRANGE: the named starting scenario.
	var human := state.fighter(0)
	var cpu := state.fighter(1)
	DuelFixture.place(human, 0.0, 0.0, PI / 2.0)
	human.weapon.reset(deg_to_rad(45.0))
	DuelFixture.place(cpu, 0.0, ContactFixture.crossed_guard_separation(rules.combatant(0), 0.005), -PI / 2.0)
	cpu.weapon.reset(deg_to_rad(-45.0))
	assert_true(ContactGauge.blades(rules, state).x > 0.0, "fixture: the guards start apart")
	walk_until[0] = state.tick + 40
	## ACT 1: both walk in until the solver forms a contact. Idle persistence
	## of a resting overlap is the domain suite's contract; this journey only
	## requires that real input can enter the contact and then leave it.
	driver.hold_move(0.0, 1.0)
	var formed := -1
	for _t in 40:
		_advance_tick(screen)
		if state.blade_contact.point_count > 0 or state.blade_contact.hold_count() > 0:
			formed = state.tick
			break
	walk_until[0] = state.tick
	driver.release_all()
	## ACT 2: the human backs off until the steel parts.
	driver.hold_move(0.0, -1.0)
	var parted := -1
	for _t in 60:
		_advance_tick(screen)
		if state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
			parted = state.tick
			break
	for _t in 3:
		_advance_tick(screen)
	var gap_after := ContactGauge.blades(rules, state).x
	var held_after := state.blade_contact.point_count + state.blade_contact.hold_count()
	## ACT 3: the human walks back in, tapping whenever it can, until it meets
	## the opponent again.
	var met: DuelEvent = null
	var seen := screen.session.events.size()
	for _t in 240:
		var distance := DuelGeometry.distance(state.fighter(0), state.fighter(1))
		driver.hold_move(0.0, 1.0 if distance > reach * 0.8 else 0.0)
		if state.fighter(0).weapon.phase == CombatPhase.Id.NEUTRAL and distance <= reach:
			driver.tap_attack()
		_advance_tick(screen)
		while seen < screen.session.events.size():
			var event: DuelEvent = screen.session.events[seen]
			seen += 1
			if met == null and parted >= 0 and event.tick > parted and (event.type == DuelEventTypes.BLADE_CONTACT or (event.type == DuelEventTypes.BODY_HIT and event.actor == 0)):
				met = event
		if met != null:
			break
	driver.release_all()
	## ASSERT
	assert_true(formed >= 0, "walking in, the swords meet (%s)" % _tally(screen))
	assert_true(parted >= 0, "backing off, the steel parts")
	assert_true(gap_after > rules.combat.separation_epsilon, "with a real gap (%.4f m)" % gap_after)
	assert_eq(held_after, 0, "and nothing held once apart")
	assert_true(met != null, "walking back in, the human meets the opponent again (%s)" % _tally(screen))
	driver.shutdown()
	await await_frames(2)


## BLADE-ESCAPE-001 through real input. The guards start 8 cm apart, the
## crossed rest the domain slide holds. The human presses forward and across
## (stick 0.6, 0.8) while the opponent stands. A held blade contact has to
## keep one identity while its point migrates, and a back-step has to part
## it. The contract after that is responsiveness, not a torso and not an
## angular allowance: on the first tick an attack is legal, one tap — press
## and release pushed before the step — is the command that step consumes.
## The weapon leaves neutral on that command. A buffered press is not left
## behind. The standing guard still takes this cut on the steel; that miss
## is not this test and is not locked in. Nothing assigns a bind, a velocity,
## or a health.
func test_a_pressed_bind_slides_and_parts_on_a_back_step() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var weapon := rules.combatant(0).weapon
	var screen := await _scenario(driver, ScenarioController.standing())
	var state := screen.session.state
	var human := state.fighter(0)
	var opponent := state.fighter(1)
	## ARRANGE: apart, at the crossed rest. The press is what forms the contact.
	DuelFixture.place(human, 0.0, 0.0, PI / 2.0)
	human.weapon.reset(deg_to_rad(45.0))
	DuelFixture.place(opponent, 0.0, ContactFixture.crossed_guard_separation(rules.combatant(0), 0.08), -PI / 2.0)
	opponent.weapon.reset(deg_to_rad(-45.0))
	assert_true(ContactGauge.blades(rules, state).x > 0.0, "fixture: the guards start apart")
	## ACT 1: press and slide. The domain witness uses this stick on this rest.
	driver.hold_move(0.6, 0.8)
	var on_blades := 0
	var warm_ticks := 0
	var kept := 0
	var identity := -1
	var lowest := INF
	var highest := -INF
	for _t in 80:
		_advance_tick(screen)
		var manifold := state.blade_contact
		if manifold.point_count == 0 or manifold.hold_active[0] == 0:
			continue
		on_blades += 1
		if manifold.is_persisted(0) and manifold.contact_id[0] == identity:
			kept += 1
		identity = manifold.contact_id[0]
		var where := manifold.fraction_a[0] + manifold.fraction_b[0]
		lowest = minf(lowest, where)
		highest = maxf(highest, where)
		if manifold.hold_normal[0] > 0.0:
			warm_ticks += 1
		if on_blades >= 10 and kept >= 5 and highest - lowest > 0.05 and warm_ticks >= 5:
			break
	var migrated := highest - lowest
	## ACT 2: a back-step is the separating input.
	driver.release_all()
	driver.hold_move(0.0, -1.0)
	var parted := -1
	var angle_at_part := 0.0
	for _t in 80:
		_advance_tick(screen)
		if state.blade_contact.phase == SwordContactSet.Phase.SEPARATED:
			parted = state.tick
			angle_at_part = human.weapon.angle
			break
	var gap_after := ContactGauge.blades(rules, state).x
	var held_after := state.blade_contact.point_count + state.blade_contact.hold_count()
	## ACT 3: the first tick an attack is legal. No frame is spent after that.
	## `push_input` delivers the tap before `advance_frame`, and one frame is
	## one tick (`AppDriver.FRAME`), so that next step is the command.
	var waited := 0
	var eligible := false
	while parted >= 0 and not WeaponSystem.can_start_attack(human, weapon) and waited < 180:
		driver.hold_move(0.0, -1.0)
		_advance_tick(screen)
		waited += 1
	eligible = parted >= 0 and WeaponSystem.can_start_attack(human, weapon)
	var released_from := human.weapon.angle
	var command_tick := state.tick
	assert_false(human.attack_held, "fixture: the attack button is up before the tap")
	driver.release_all()
	driver.tap_attack()
	_advance_tick(screen)
	var started := _first_after(screen, DuelEventTypes.ATTACK_STARTED, 0, command_tick - 1)
	var answer := _first_after(screen, DuelEventTypes.ATTACK_RELEASED, 0, command_tick - 1)
	var drift := absf(released_from - angle_at_part)
	## ASSERT
	## Measured once with the four-tick wait removed: waited 0, drift 0,
	## command tick equal to the parting tick, phase LAUNCH. This scene's
	## parting tick is already a legal attack, so there is no angular
	## allowance. A later change that spends ticks before the attack is legal
	## fails here and has to be re-read, rather than hiding inside 0.35 rad.
	assert_true(on_blades >= 10, "the press holds the blades (%d ticks)" % on_blades)
	assert_true(warm_ticks >= 5, "the hold carries impulse (%d ticks)" % warm_ticks)
	assert_true(kept >= 5, "one contact identity lasts (%d ticks)" % kept)
	assert_true(migrated > 0.05, "the point migrates along the blades (%.3f)" % migrated)
	assert_true(parted >= 0, "a back-step parts the steel")
	assert_true(gap_after > rules.combat.separation_epsilon, "with a real gap (%.4f m)" % gap_after)
	assert_eq(held_after, 0, "and nothing is held once apart")
	assert_true(eligible, "an attack is legal after the part (waited %d ticks, blade %.4f rad off the parting angle)" % [waited, drift])
	assert_eq(waited, 0, "this parting tick is already legal, so none are spent waiting")
	assert_eq(released_from, angle_at_part, "and the blade is still at the parting angle")
	assert_eq(command_tick, parted + waited, "the tap is that first legal tick, not a later one")
	assert_true(started != null and started.tick == command_tick, "that step starts the attack (%s)" % _tally(screen))
	assert_true(answer != null and answer.tick == command_tick, "and releases it in the same command (%.4f rad of return over %d ticks)" % [drift, waited])
	assert_true(CombatPhase.is_swinging(human.weapon.phase) or human.weapon.phase == CombatPhase.Id.LAUNCH, "the weapon leaves neutral on that command (phase %d)" % human.weapon.phase)
	assert_true(human.press_tick < 0 and human.buffered_press_tick < 0, "the tap is consumed; nothing is held or buffered")
	driver.shutdown()
	await await_frames(2)


## GLANCE-001 through real input, from a named starting scenario: once the
## round is live the human stands at rest and the opponent 2.0 m ahead, 0.3 m
## to the side, its sword at rest turned out to +1.2 rad. The human taps
## (keys) and its cut meets the opponent's blade before any body: a solved
## steel contact (positive impulse) whose consequence is immediate and
## physical — the cut's θ̇ is cut against its swing by the contact — yet it is
## not arrested: three ticks later the cut is still swinging. What it does
## after is not claimed (there is no attack identity to tie a later hit to this
## swing). The scene is a fixture point, not a band: a probe of 180 resting
## guards found 3 glances, so a change to the steel may move it.
func test_a_tap_glancing_off_a_guard_is_redirected_but_not_stopped() -> void:
	var driver := AppDriver.boot(7)
	await await_frames(1)
	var rules := StandardDuelRules.create()
	var screen := await _scenario(driver, ScenarioController.standing())
	var state := screen.session.state
	## ARRANGE: the named starting scenario.
	DuelFixture.place(state.fighter(0), 0.0, 0.0, 0.0)
	state.fighter(0).weapon.reset(-rules.combatant(0).weapon.guard_angle)
	DuelFixture.place(state.fighter(1), 2.0, -0.3, PI)
	state.fighter(1).weapon.reset(1.2)
	assert_true(ContactGauge.blades(rules, state).x > 0.0, "fixture: the swords start apart")
	assert_true(WeaponSystem.can_start_attack(state.fighter(0), rules.combatant(0).weapon), "fixture: the human can strike")
	## ACT: one tap, then the cut's first contact and three ticks after it.
	driver.tap_attack()
	var contact: DuelEvent = null
	var flesh_first := false
	var seen := screen.session.events.size()
	var after := -1
	for _t in 40:
		_advance_tick(screen)
		while seen < screen.session.events.size():
			var event: DuelEvent = screen.session.events[seen]
			seen += 1
			if contact == null and event.type == DuelEventTypes.BLADE_CONTACT:
				contact = event
				after = state.tick + 3
			elif contact == null and event.type == DuelEventTypes.BODY_HIT and event.actor == 0:
				flesh_first = true
		if contact != null and state.tick >= after:
			break
	driver.release_all()
	var weapon := state.fighter(0).weapon
	## ASSERT
	assert_true(contact != null and not flesh_first, "the tap meets the opponent's steel before any body (%s)" % _tally(screen))
	if contact != null:
		assert_eq(contact.actor, 0, "the human's cut is the attack")
		assert_true(contact.number(DuelEventKeys.IMPULSE) > 0.0, "a solved contact (%.3f N·s)" % contact.number(DuelEventKeys.IMPULSE))
		assert_true(float(contact.data[DuelEventKeys.DELTA_0]) * weapon.swing_dir < 0.0, "the contact cuts the swing's θ̇ (Δθ̇ %+.3f rad/s)" % float(contact.data[DuelEventKeys.DELTA_0]))
		assert_false(bool(contact.data[DuelEventKeys.ARRESTED_0]), "but does not arrest it")
		assert_true(CombatPhase.is_swinging(weapon.phase), "three ticks on, the cut is still swinging (phase %d, θ̇ %+.2f)" % [weapon.phase, weapon.speed])
		var control := rules.combatant(0).weapon.control_speed
		## `class` is closing speed (light / solid / strong). `ContactReading`
		## is what the contact did to the cut. This glance is solid and not arrested.
		assert_eq(contact.text(DuelEventKeys.CONTACT_CLASS), String(ContactResolver.CLASS_SOLID), "the clang class is the closing-speed band, solid")
		assert_eq(ContactReading.classify(contact, control, control), ContactReading.GLANCE, "and its reading is a glance: the cut kept %.0f%% of its progress" % (100.0 * contact.number(DuelEventKeys.PROGRESS_AFTER) / maxf(contact.number(DuelEventKeys.PROGRESS_BEFORE), 1e-9)))
	driver.shutdown()
	await await_frames(2)
