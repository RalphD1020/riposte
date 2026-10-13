extends TestCase

## CONTACT-INTEGRITY-SHIP: the long contact corpora (`pnpm test:contact:ship`,
## an audit tier). CONTACT-INTEGRITY owns the laws — no crossing, the slop,
## a motor cannot push through, mirror, the bounded storm fallback — through
## designed witnesses in the gate. This asks a different question: do the
## unusual combinations long representative play reaches ever break them?
## Seeded pilots, the real tick, every live tick measured. Run at a release
## checkpoint, never while implementing.
##
## See also: /docs/reference/testing.md
## See also: /docs/concepts/combat.md

## Acceptance bound for the hold-budget fallback (live ticks per exhaustion).
const HOLD_BUDGET_TICKS_PER_FALLBACK := 5000

var _rules: DuelRules


func _init() -> void:
	suite_name = "CONTACT-INTEGRITY-SHIP"
	_rules = DuelFixture.rules()

## The development corpus the solver was built against doubles as its
## adversarial set: a fallback is legal here, only bounded.
func test_live_duels_hold_every_contact_rigid() -> void:
	_assert_corpus_rigid(ContactGauge.DEVELOPMENT_SEEDS, 5000, false)


## The ship corpus is the representative one: it expects every fallback at
## zero, so recurring fallback use can never pass as ordinary gameplay.
func test_the_ship_corpus_holds_every_contact_rigid() -> void:
	_assert_corpus_rigid(range(ContactGauge.SHIP_SEEDS_FROM, ContactGauge.SHIP_SEEDS_FROM + ContactGauge.SHIP_SEEDS), 30000, true)


## Play `seeds` with wandering pilots and measure every live tick.
func _assert_corpus_rigid(seeds: Array, least_live: int, representative: bool) -> void:
	var live := 0
	var held_blade := 0
	var held_body := 0
	var blade_worst := 0.0
	var body_worst := 0.0
	var crossings := 0
	var saturated := 0
	var clashes := 0
	var hits := 0
	var ccd_caps := 0
	var contact_caps := 0
	var hold_caps := 0
	var turn_guards := 0
	var dropped := 0
	var pivot_caps := 0
	var most_points := 0
	var unsound := 0
	var pending_worst := 0.0
	var unresolved := 0
	for seed_value: int in seeds:
		print("  · CONTACT-INTEGRITY-SHIP seed %d" % seed_value)
		var pending_body: Array[bool] = [false, false]
		var runner := SimRunner.create(_rules, seed_value)
		var first := Pilot.wander(seed_value, 11)
		var second := Pilot.wander(seed_value, 23)
		for _tick in ContactGauge.DUEL_TICKS:
			if runner.state.is_finished():
				break
			runner.push(first.command(runner.state, 0), second.command(runner.state, 1))
			if runner.state.phase != MatchPhase.Id.ROUND_ACTIVE:
				continue
			live += 1
			var state := runner.state
			var a := state.fighter(0)
			var b := state.fighter(1)
			var blades := ContactGauge.blades(_rules, state)
			if a.is_alive() and b.is_alive():
				if ContactGauge.centrelines(_rules, state) <= SimMath.EPSILON:
					crossings += 1
				if state.blade_contact.phase != SwordContactSet.Phase.SEPARATED:
					blade_worst = maxf(blade_worst, -blades.x)
					if blades.x <= 0.0:
						held_blade += 1
				elif blades.x < 0.0:
					pending_worst = maxf(pending_worst, -blades.x)
			for slot in 2:
				var wielder := state.fighter(slot)
				var target := state.opponent_of(slot)
				var was_pending := pending_body[slot]
				pending_body[slot] = false
				if not wielder.is_alive() or not target.is_alive():
					continue
				var gap := ContactGauge.body(_rules, wielder, target)
				var lifecycle := state.weapon_body_contacts[slot].phase
				if lifecycle == WeaponBodyContact.Phase.OUTSIDE:
					## A touch the sweep has not resolved yet — it will be, as
					## a new contact, on the next tick.
					if gap < 0.0:
						pending_worst = maxf(pending_worst, -gap)
						pending_body[slot] = true
						if was_pending:
							unresolved += 1
					continue
				body_worst = maxf(body_worst, -gap)
				if gap <= 0.0 and lifecycle == WeaponBodyContact.Phase.CONSTRAINING:
					held_body += 1
		saturated += runner.count(DuelEventTypes.CONTACT_SATURATED)
		clashes += runner.count(DuelEventTypes.BLADE_CONTACT)
		hits += runner.count(DuelEventTypes.BODY_HIT)
		var counters := runner.simulation.diagnostics
		ccd_caps += counters.ccd_cap_hits
		contact_caps += counters.contact_cap_hits
		hold_caps += counters.rehold_budget_exhausted
		turn_guards += counters.position_guard_hits
		dropped += counters.meaningful_contacts_dropped
		pivot_caps += counters.pivot_cap_hits
		most_points = maxi(most_points, counters.max_manifold_points)
		if not runner.is_sound():
			unsound += 1
	## The corpus has to actually press contacts for its silence to mean anything.
	assert_true(live > least_live, "fixture: the corpus is long live play (%d ticks)" % live)
	assert_true(clashes > 20 and hits > 20, "fixture: it clashes and lands hits (%d clashes, %d hits)" % [clashes, hits])
	assert_true(held_blade > 100, "fixture: blades are held against each other after a clash (%d ticks)" % held_blade)
	assert_true(held_body > 100, "fixture: swords rest on living bodies after a hit (%d ticks)" % held_body)
	assert_true(blade_worst <= ContactGauge.allowed(_rules), "no held blade sinks into another beyond the slop (worst %.4f m)" % blade_worst)
	assert_true(body_worst <= ContactGauge.allowed(_rules), "no held blade sinks into a living torso beyond the slop (worst %.4f m)" % body_worst)
	## A touch begun in the last instants of a tick (or by the correction of a
	## neighbouring held contact) is the sweep's: shallow, and resolved as a
	## contact on the very next tick.
	assert_true(pending_worst <= _rules.combat.contact_max_correction, "an unresolved touch is never deeper than one correction (worst %.4f m)" % pending_worst)
	assert_eq(unresolved, 0, "and the next tick always resolves it")
	assert_eq(crossings, 0, "no blade centreline ever crosses another")
	assert_eq(saturated, 0, "the contact loop never runs out of budget in live play")
	## Every fixed cap is a deterministic fallback, and healthy play takes none.
	assert_eq(ccd_caps, 0, "no sweep runs out of substeps")
	assert_eq(contact_caps, 0, "no tick runs out of contacts")
	assert_eq(turn_guards, 0, "no position pass needs the degenerate-pin turn guard")
	## The re-hold budget is a named fallback: a held contact under very fast
	## rotation can re-cross more often than the budget allows, and the rest of
	## that tick is carried without tunnelling (CONTACT-FALLBACK-001) — the overlap bounds above
	## still hold on those ticks. Legal, so adversarial play is only bounded;
	## representative play expects none.
	## Every feature pair keeps its own manifold (TWO-POINT-001), so a hilt
	## lock's three constraints are three rows: no real constraint is ever
	## dropped, for any feature, and the exact block always finishes.
	assert_eq(pivot_caps, 0, "the exact contact block never reaches its pivot cap (%d)" % pivot_caps)
	if representative:
		assert_eq(hold_caps, 0, "representative play never exhausts the re-hold budget (%d in %d live ticks)" % [hold_caps, live])
		assert_eq(dropped, 0, "no feature pair — blade, crossguard or handle — ever drops a real constraint (%d)" % dropped)
		assert_true(most_points > SwordContactSet.POINTS_PER_PAIR, "fixture: live play reaches contacts no single feature pair could hold (%d points at most)" % most_points)
	else:
		assert_true(hold_caps * HOLD_BUDGET_TICKS_PER_FALLBACK <= live, "adversarial play exhausts the re-hold budget at most once per %d live ticks (%d in %d)" % [HOLD_BUDGET_TICKS_PER_FALLBACK, hold_caps, live])
	assert_eq(unsound, 0, "no duel leaves its legal state set (finite, in range)")
