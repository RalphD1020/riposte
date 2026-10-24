extends TestCase

## REPLAY: same commands → same duel; records verify; tampering is caught;
## random play never breaks state invariants (COMBAT §77, PLAN Phase 16).
##
## Implements: /spec/invariants.md#sim-002
## See also: /docs/concepts/simulation.md

const TICKS := 1800


func _init() -> void:
	suite_name = "REPLAY"


func _played(seed_value: int, keep_hashes: bool = false) -> SimRunner:
	var runner := SimRunner.create(DuelFixture.rules(), seed_value)
	runner.run(Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23), TICKS, keep_hashes)
	return runner


func test_identical_commands_reproduce_identical_duels() -> void:
	var first := _played(5, true)
	var second := _played(5, true)
	assert_true(first.count(DuelEventTypes.ATTACK_RELEASED) > 10, "precondition: plenty of attacks")
	assert_true(first.count(DuelEventTypes.BODY_HIT) + first.count(DuelEventTypes.BLADE_CONTACT) > 3, "precondition: real contacts")
	assert_eq(first.hashes.size(), second.hashes.size(), "same length")
	assert_eq(first.hashes, second.hashes, "every tick hash matches")


func test_a_pit_recording_is_version_59_and_refused_on_the_open_disc() -> void:
	var pit := StandardDuelRules.pit()
	var runner := SimRunner.create(DuelFixture.mirror(pit), 3)
	runner.idle(20)
	runner.seal()
	assert_eq(runner.record.rules_version, 60, "the pit records version 60")
	assert_true(runner.record.matches_rules(pit), "and matches those rules")
	assert_false(runner.record.matches_rules(StandardDuelRules.create()), "version 58 is a different rules set")
	assert_eq(ReplayVerifier.verify(runner.record, pit), ReplayVerifier.VERIFIED, "it replays on the pit")
	assert_eq(ReplayVerifier.verify(runner.record, StandardDuelRules.create()), ReplayVerifier.RULES_MISMATCH, "and is refused on the open disc")
	var open := _played(5)
	assert_eq(open.record.rules_version, 58, "fixture: the golden path is still version 58")
	assert_false(open.record.matches_rules(pit), "a version-58 recording is not the pit")


func test_different_seeds_diverge() -> void:
	assert_ne(_played(5).record.final_hash, _played(6).record.final_hash, "different inputs, different duels")


func test_record_verifies_and_tampering_is_caught() -> void:
	var runner := _played(9)
	var rules := DuelFixture.rules()
	assert_eq(ReplayVerifier.verify(runner.record, rules), ReplayVerifier.VERIFIED, "honest record verifies")
	var forged := ReplayRecord.from_dictionary(runner.record.to_dictionary())
	for index in range(1, forged.commands_0.size(), PlayerCommand.PACKED_STRIDE):
		forged.commands_0[index] = -forged.commands_0[index]
	assert_eq(ReplayVerifier.verify(forged, rules), ReplayVerifier.HASH_MISMATCH, "a forged command stream is detected")
	rules.version += 1
	assert_eq(ReplayVerifier.verify(runner.record, rules), ReplayVerifier.RULES_MISMATCH, "replays pin their rules")


func test_record_survives_json() -> void:
	var runner := _played(3)
	var text := JSON.stringify(runner.record.to_dictionary())
	var restored := ReplayRecord.from_dictionary(JSON.parse_string(text) as Dictionary)
	assert_true(restored != null, "parsed back")
	assert_eq(restored.tick_count(), runner.record.tick_count(), "same length")
	assert_eq(ReplayVerifier.verify(restored, DuelFixture.rules()), ReplayVerifier.VERIFIED, "still verifies after JSON")
	assert_true(ReplayRecord.from_dictionary({"format": 99}) == null, "unknown format rejected")
	assert_true(ReplayRecord.from_dictionary({"format": ReplayRecord.FORMAT_VERSION, "commands_0": [1, 2, 3], "commands_1": []}) == null, "malformed streams rejected")


## A recording names the state-hash layout it was hashed under, and is refused
## across a layout change (STAMINA-003 moved every hash without changing the
## game): the replay says "different schema", never "nondeterminism".
func test_a_recording_is_refused_across_a_state_layout_change() -> void:
	## ARRANGE
	var rules := DuelFixture.rules()
	var record := ReplayRecord.begin(rules, 7)
	assert_eq(record.state_layout_version, StateHasher.LAYOUT_VERSION, "fixture: a new recording names the current layout")
	assert_true(record.matches_rules(rules), "fixture: and matches its own rules")
	var restored := ReplayRecord.from_dictionary(record.to_dictionary())
	assert_true(restored != null and restored.matches_rules(rules), "fixture: the layout survives serialization")
	## PERTURB: a recording made under an older layout.
	var older := record.to_dictionary()
	older[ReplayRecord.KEY_STATE_LAYOUT] = StateHasher.LAYOUT_VERSION - 1
	var legacy := ReplayRecord.from_dictionary(older)
	## ACT + ASSERT
	assert_true(legacy != null, "fixture: the older recording still parses")
	assert_false(legacy.matches_rules(rules), "but is refused against the current layout")
	assert_eq(ReplayVerifier.verify(legacy, rules), ReplayVerifier.RULES_MISMATCH, "and verification says so, rather than a hash mismatch")


## Content schema 4 drops `grip_damage_factor` from the fighter fingerprint.
## A schema-3 recording is refused. Nothing in the product writes a replay to
## disk: `MatchSession` holds the record in memory, and `user://` persists
## settings only, so there is no library to migrate.
func test_a_recording_is_refused_across_a_content_schema_change() -> void:
	var rules := DuelFixture.rules()
	var record := ReplayRecord.begin(rules, 7)
	assert_eq(record.content_schema_version, CombatantPhysicsSpec.CONTENT_SCHEMA_VERSION, "fixture: a new recording names the current schema")
	var older := record.to_dictionary()
	older[ReplayRecord.KEY_CONTENT_SCHEMA] = CombatantPhysicsSpec.CONTENT_SCHEMA_VERSION - 1
	var legacy := ReplayRecord.from_dictionary(older)
	assert_true(legacy != null, "fixture: the older recording still parses")
	assert_false(legacy.matches_rules(rules), "a schema-3 recording is not these rules")
	assert_eq(ReplayVerifier.verify(legacy, rules), ReplayVerifier.RULES_MISMATCH, "and it is refused as a rules mismatch")


## On the rules-55 trajectory, a blade that enters a former hand or handle
## disc while staying outside the torso changes no health. The first health
## change, when the duel has one, is a torso entry. Rules 54 was never
## committed and no per-tick dump of it was saved, so this is the causal
## account the tree can still check: the deleted grip query is not an
## authoritative event on the new run. It is not a field diff against the
## old binary.
func test_a_hand_crossing_is_not_an_authoritative_change() -> void:
	for seed_value: int in [17, 3]:
		var runner := SimRunner.create(DuelFixture.rules(), seed_value)
		var pilots: Array[Pilot] = [Pilot.wander(seed_value, 11), Pilot.wander(seed_value, 23)]
		var health := [runner.state.fighter(0).health, runner.state.fighter(1).health]
		var hand_tick := -1
		var wound_tick := -1
		while runner.state.tick < TICKS and wound_tick < 0:
			runner.push(pilots[0].command(runner.state, 0), pilots[1].command(runner.state, 1))
			var crossed := _hand_only_crossing(runner.state)
			if crossed and hand_tick < 0:
				hand_tick = runner.state.tick
			if runner.state.fighter(0).health != health[0] or runner.state.fighter(1).health != health[1]:
				wound_tick = runner.state.tick
			elif crossed:
				assert_eq(runner.state.fighter(0).health, health[0], "seed %d tick %d: a hand crossing does not wound slot 0" % [seed_value, runner.state.tick])
				assert_eq(runner.state.fighter(1).health, health[1], "seed %d tick %d: a hand crossing does not wound slot 1" % [seed_value, runner.state.tick])
		assert_true(wound_tick > 0, "fixture: seed %d does take a wound" % seed_value)
		## `step` stamps events with the tick it is resolving, then increments.
		var resolved := wound_tick - 1
		var hit: DuelEvent = null
		for event: DuelEvent in runner.events:
			if event.type == DuelEventTypes.BODY_HIT and event.tick == resolved:
				hit = event
				break
		assert_true(hit != null, "seed %d: the first health change is a body hit (tick %d)" % [seed_value, resolved])
		if hit != null:
			assert_eq(hit.text(DuelEventKeys.REGION), DuelEventKeys.REGION_TORSO, "seed %d: and that hit is the torso" % seed_value)
		assert_true(hand_tick < 0 or hand_tick <= wound_tick, "seed %d: a hand-only crossing was either absent or not after the wound (hand %d, wound %d)" % [seed_value, hand_tick, wound_tick])


## True when either blade has entered the other's hand or handle disc and is
## still outside that fighter's torso circle.
func _hand_only_crossing(state: MatchState) -> bool:
	var rules := DuelFixture.rules()
	for attacker in 2:
		var sword := state.fighter(attacker)
		var body := state.fighter(1 - attacker)
		var spec_a := rules.combatant(attacker)
		var spec_b := rules.combatant(1 - attacker)
		var pose := WeaponKinematics.pose_at(sword.x, sword.y, sword.facing, sword.weapon.angle, spec_a, BladePose.new())
		var theirs := WeaponKinematics.pose_at(body.x, body.y, body.facing, body.weapon.angle, spec_b, BladePose.new())
		var torso := _replay_disc_gap(pose, spec_a.weapon, Vector2(body.x, body.y), spec_b.fighter.hurt_radius)
		if torso <= 0.0:
			continue
		var weapon := spec_b.weapon
		var along := PackedFloat64Array([weapon.offhand_grip_radius, weapon.dominant_grip_radius, (weapon.offhand_grip_radius + weapon.dominant_grip_radius) * 0.5])
		var radii := PackedFloat64Array([spec_b.fighter.hand_radius, spec_b.fighter.hand_radius, weapon.handle_radius])
		for i in 3:
			if _replay_disc_gap(pose, spec_a.weapon, Vector2(theirs.point_x(along[i]), theirs.point_y(along[i])), radii[i]) < 0.0:
				return true
	return false


func _replay_disc_gap(pose: BladePose, weapon: WeaponDefinition, point: Vector2, disc: float) -> float:
	var hx := pose.point_x(weapon.blade_base_radius)
	var hy := pose.point_y(weapon.blade_base_radius)
	var tx := pose.point_x(weapon.tip_radius)
	var ty := pose.point_y(weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, point.x, point.y)
	return Vector2(point.x - lerpf(hx, tx, t), point.y - lerpf(hy, ty, t)).length() - disc - weapon.blade_radius


## Pinned final hashes. Presentation work of any size must leave these alone;
## only a deliberate rules change (with its `DuelRules.version` bump) may
## re-record them, and only beside a reviewed metrics re-pin (below).
## Last re-recorded for rules 58, layout 9. Seed 3's hash and counts are the
## rules-57 pin: that duel never put both hilt caps on each other. Seeds 5,
## 9 and 17 re-roll from the first mutual start-cap. The field is still
## `impact_authority`. Forcing the dip off reproduces the rules-55 metric
## table on every seed. With the dip, the first steel episode and the first
## later pose are state ticks 259/260, 121/131, 134/135 and 688/690 (seeds
## 3, 5, 9, 17). The pose move is the next guard return, not the solver:
## seed 3's slot 0 is in recovery and its speed is 1.1847 against 1.1938.
## Authority then returns above 0.9 within a few tenths of a second of its
## low (ticks 287, 353, 1656, 996). It is not left on the floor for the
## round. The first health difference is a changed amount on a hit both
## duels still land (269, 724, 149, 700). The first event one duel has and
## the other does not is 291, 382, 763 and 783. Seeds 3 and 5 keep this pin
## after recovery's exponential moved from platform `exp` to `SimMath.exp_minus`.
## Seeds 9 and 17 change hash only; their metric rows do not, so no counted
## event moved. No solver, motor, or radius
## was retuned. The rules-55 pin this replaces had dropped `grip_struck`:
## body hits fell on every seed (36→27, 17→14, 17→10, 22→15) because grip
## wounds were gone. Seed 17 kept its attacks (18), kills (3) and rounds
## (3). Seeds 3, 5 and 9 changed round flow because that missing chip damage
## changed who was alive. Blade contacts rose where a cut that used to spend
## itself on a hand met steel.
func test_golden_final_hashes_are_pinned() -> void:
	var golden := {
		3: "63692944d8ae2e9b721914589ead052d195dfe4f706efe876301015f0ebc380d",
		5: "879e861ab4ed7a25717e4401f5f119d10a725ca58909d0f1ccb0c255f4c54dd7",
		9: "57159087f754ce6615f779fdbde85423e41b05c1dd209552775d7ac9a544646c",
		17: "842046ff6a553d8ef65d4333e06a49d232fb01575b1cfd937cd0873f00b6236e",
	}
	for seed_value: int in golden:
		var runner := _played(seed_value)
		assert_true(runner.count(DuelEventTypes.ATTACK_RELEASED) > 10, "precondition: seed %d fought" % seed_value)
		assert_eq(runner.record.final_hash, str(golden[seed_value]), "seed %d final hash is unchanged" % seed_value)


## What the golden duels did, pinned beside their hashes. A rules change that
## moves a hash must also show here what changed in the fighting — clashes,
## parries, binds, hits by kind, kills, ring-outs — and the re-pin documents
## why each difference is intended (SIM-002).
##
## Rules 22 review (corpus totals, rules 21 → 22): kills 7 → 7, rounds 7 → 7,
## ring-outs 0 → 0, parries 15 → 15 — lethality and round flow unchanged.
## Body hits 55 → 50, pokes 10 → 7, attacks 97 → 80, blade collisions
## 45 → 35: loads now sit lateral of the body instead of behind it, so fewer
## blades cross. Binds 0 → 3: near the centre the pommel counter-moves as the
## blade sweeps, so a point's closing speed is lower for the same ω and more
## low-speed contacts fall under `bind_speed` (the speed-zeroing bind that
## CONTACT-MANIFOLD-001's friction replaces next).
##
## Rules 23 review (corpus totals, rules 22 → 23): kills 7 → 7, rounds 7 → 7,
## ring-outs 0 → 0 — lethality and round flow unchanged. Blade collisions
## 35 → 57, parries 15 → 29, attacks 80 → 101: with the torso the blade
## actually strikes 7.5 cm smaller than the footprint, blades meet before a
## body far more often, so exchanges run longer for the same kills. Body hits
## 50 → 60 on 26 % more attacks (hits per attack 0.63 → 0.59). Pokes 7 → 11
## was not predicted, so seed 9 (0 → 3) was traced: every poke is a settled
## point — attacker NEUTRAL or RECOVERY, |θ| ≤ 7°, no burst, the tip (blade
## fraction 1.0) meeting the torso at 1.42–1.50 m centre distance (the new
## 1.46 m strike reach) while walking in at 1.5–2.3 m/s. None is an active cut
## read as a point. The same seed with the 0.27 m hurt circle plays a
## different duel (11 attacks, not 24), so the count moved with the
## trajectory, not the classification. Criticals 2 → 1, binds 3 → 4.
##
## Rules 24 review (corpus totals, rules 23 → 24): ring-outs 0 → 0, kills
## 7 → 8 and rounds 7 → 8 (seed 17 finishes a third round inside the window).
## The rear hand's surface sat inside the torso nearly everywhere, so the
## carriage moved out: Long Guard 0.235 → 0.29 m forward (Long Guard reach
## +5.5 cm, strike reach 1.46 → 1.52 m), Ready 0.09 → 0.14 m lateral. The
## longer point lands first more often: body hits 60 → 76 on fewer attacks
## (101 → 89; hits per attack 0.59 → 0.85), blade collisions 57 → 43, parries
## 29 → 21, binds 4 → 7, criticals 1 → 3. Pokes 11 → 19: seeds 3 and 5 traced
## — all twelve are points (NEUTRAL, RECOVERY or STAGGER, |θ| ≤ 12°, no
## burst, the tip at 1.47–1.59 m centre distance), none an active cut read as
## a point. Two had a drifting blade (ω −4 to −5 rad/s); classification does
## not read ω, which is noted for the contact work, not changed here.
##
## Rules 25 review (corpus totals, rules 24 → 25; two changes, one version).
## (1) Drawing the sword on the orbit with no presentation offset showed v24's
## pommel 0.19 m behind the hands, inside the belly near the centre, and the
## loads folding the near arm onto the shoulder; the orbit now carries the
## whole rigid sword clear: Long Guard 0.29 → 0.41 m forward (strike reach
## 1.52 → 1.64 m), Ready 0.255 → 0.37, Gather 0.19 → 0.33, Load 0.12 → 0.30,
## Load lateral 0.25 → 0.20. (2) That made contacts near the hands reachable,
## where a weapons-only blade response spun a sword past the guardrail, so the
## wielders' bodies now share each blade contact's impulse
## (SwordContactSolver). Ring-outs 0 → 0, kills 8 → 9 and rounds 8 → 9 (seed 3
## finishes a second round), attacks 89 → 87, binds 7 → 7 — lethality and round
## flow unchanged. Blade collisions 43 → 47, parries 21 → 14, body hits
## 76 → 70, pokes 19 → 16, criticals 3 → 2: the longer swords meet in front
## of the bodies a little more and land a little less. Orbit alone (before
## (2)): blade collisions 53, pokes 9, body hits 75 — so (2) moves single
## seeds a lot (a chaotic duel) while the totals stay close. Read from the
## totals, not traced per seed. Pinned while v25 is open (FUZZ seed 13, the
## CPU overcharge law and the head clearance are unresolved); balance is
## retuned on this geometry later (7B.8), never by pulling the hands back in.
## (Those three were resolved and v25 accepted on a clean full run.)
##
## Rules 26 review (corpus totals, rules 25 → 26): one contact mechanics
## (ContactMechanics) for every sword contact — impulse `(1 + e)·v_n / k`,
## energy `½(1 − e²)·v_n² / k` with `k` the target's resisting body, the
## attacker's coupled body and the weapon coordinate through its lever. Cut
## severity was a striking mass's `½·m·v_n²`; stagger was `m·v_n`; the
## blade-on-blade bodies used the full fighter mass; the persistent
## sword-body constraint used yet another. References (impulse, cut and
## thrust severity) are derived from the same mechanics, and the bite peaks at
## the derived centre of percussion (0.648 of the blade; was authored 0.70).
## Attacks 87 → 84, criticals 2 → 3, ring-outs 0 → 0, body hits per kill
## 7.8 → 7.9 — a landed hit is worth what it was. Fewer land: body hits
## 70 → 55, kills and rounds 9 → 7 (seeds 5 and 17 finish one round fewer),
## while blade collisions 47 → 55, parries 14 → 17, binds 7 → 9, pokes
## 16 → 8 — a clash near the hands now pushes the coupled bodies apart
## instead of whipping the swords out of line, so the blades stay in each
## other's way. Read from the totals, not traced per seed.
##
## Rules 27 review (corpus totals, rules 26 → 27): a point no longer has its
## own mass model. v26 solved POKE/THRUST through the bodies alone and skipped
## the sword's reaction; now every body contact uses the same `k` with the
## weapon's lever on the contact normal, and points read the same dissipated
## energy against the thrust reference. A point driven along its blade has a
## zero lever and is unchanged; one met off its axis gives way and is
## deflected. Cuts are untouched — seed 9, the one golden duel with no point
## strike, keeps its hash bit for bit, which is the proof the change is
## confined to points. Seeds 3, 5 and 17 diverge from their first poke and
## then play different duels: pokes 8 → 5, kills 7 → 7, rounds 7 → 7,
## ring-outs 0 → 0, attacks 84 → 85, body hits 55 → 58, blade collisions
## 55 → 52, parries 17 → 16, binds 9 → 7, criticals 3 → 4. Lethality and round
## flow unchanged; read from the totals, not traced per seed.
##
## Rules 28 review (corpus totals, rules 27 → 28). The sword is held the way
## a hand-and-a-half sword is: the dominant hand just under the guard, the off
## hand just above the pommel (markers 0.150 / 0.225 → 0.070 / 0.1865 m from
## the pommel, derived from the measured handle). The orbit's reference point
## stays at 0.1875 m, so θ, `C(θ)` and every authoritative sword point are
## unchanged; what moves is the centre of percussion about the hands (blade
## fraction 0.648 → 0.633), and so the bite curve's peak. Separately, exactly
## parallel blades now meet at their overlap's midpoint instead of slot 0's
## blade end (a slot bias a mirrored head-on clash exposed). Seed 3 keeps its
## hash; with the parallel fix backed out seeds 5, 9 and 17 still move, so the
## percussion shift is what moves them. Attacks 85 → 90, blade collisions
## 52 → 60, parries 16 → 15, binds 7 → 11, body hits 58 → 57, pokes 5 → 7,
## criticals 4 → 4, kills and rounds 7 → 6 (seed 5 finishes one round fewer),
## ring-outs 0 → 0. Read from the totals, not traced per seed.
##
## Rules 29 review (rules 28 → 29), seed by seed. Held contacts are rigid
## every tick (RIGID-CONTACT-001): v28 resolved a clash once and then let a
## still-driven blade slide through the guard it met, and let a sword sink up
## to 22 cm into a torso it was resting on. Read by playing these same seeds
## with the constraint inert (`InertRigidSolver`) beside the real one:
## - every first impact is bit-identical (seed 3: 79.8 at tick 119; seed 9:
##   65.7 at 127; seed 17: 75.5 at 123) — CONTACT-INTEGRITY pins this;
## - without the constraint, 9 of 24 strong hits (≥ 10 damage) followed, within
##   15 ticks, a blade passing through the opponent's blade (3.9–4.4 cm overlap
##   — centrelines crossed) or one embedded in the torso (1.2–2.8 cm); one of
##   seed 5's two kills was such a hit. With the constraint none of these
##   exist, and every remaining strong hit had no prior overlap;
## - inert → real over the four seeds: kills 8 → 4, strong hits 24 → 17,
##   damage 1385 → 847; then each duel diverges from its first held contact.
## Totals v28 → v29: attacks 90 → 102, blade collisions 60 → 69, parries
## 15 → 21, binds 11 → 9, body hits 57 → 50, pokes 7 → 15, criticals 4 → 2,
## kills 6 → 4, rounds 6 → 5, ring-outs 0 → 1. Guards hold, so less damage
## lands; lethality of a landed clean cut is unchanged.
##
## Rules 30 review (rules 29 → 30). v29 ended any swing a held contact left
## below the deflect fraction — including a cut still beating a guard aside, or
## one barely out of its wind-up that only grazed something. Now a hold ends a
## cut only when it opposed and arrested its progress (CONTACT-INTEGRITY:
## BLOCKED and GLANCING scenes). Played old law beside new on these seeds: each
## duel is identical up to its first hold the new law no longer ends (ticks
## 578 / 693 / 1388 / 899 for seeds 3 / 5 / 9 / 17), then diverges. Of the
## new law's 71 hits only 3 (84 damage) came from a swing the old law would
## have ended; the rest are the diverged duels. Totals v29 → v30: attacks
## 102 → 101, blade collisions 69 → 58, parries 21 → 19, binds 9 → 10, body
## hits 50 → 71, pokes 15 → 18, criticals 2 → 1, kills 4 → 6, rounds 5 → 6,
## ring-outs 1 → 0. Four seeds over-read that: on the 40-seed ship corpus the
## change is neutral — hits 647 → 626, kills 54 → 56, damage 10833 → 10870,
## clashes 638 → 677 — so the swing here is divergence, not a new damage source.
##
## Rules 31 review (rules 30 → 31). Three changes, one version. (1) The hilt
## track is calibrated to the right-lead Wolf rig: Long Guard 0.41 → 0.63 m
## forward (the limiting left arm at 0.96 of its reach, shoulders unmoved),
## a 15° knot for a rounded top, Ready / Gather forward with it (0.37 → 0.56,
## 0.33 → 0.45) so the hands travel no faster per radian than before; strike
## reach 1.64 → 1.86 m. (2) Bodies are a fourth row in the persistent-contact
## block: v30 cleared a sword-on-torso overlap by moving the bodies and could
## drive them up to 2.4 mm into each other (random play, seed 2 tick 128).
## (3) A separated body pair rests 1 nm outside touching, so rounding never
## decides whether the next tick sees a contact (mirrored scenes diverged at
## exactly touching). The geometry changes from the first tick, so every duel
## diverges at once; read from the 40-seed ship corpus instead (v30 → v31):
## attacks 989 → 1020, clashes 677 → 763, body hits 626 → 669, kills 56 → 49,
## damage 10870 → 9199 (17.4 → 13.7 per hit), pokes 91, ring-outs 0, no
## fallback of any kind. Longer, point-forward guards meet sooner: more blade
## and point contacts at reach, fewer clean lethal cuts. Golden totals v30 →
## v31: attacks 101 → 96, blade collisions 58 → 87, parries 19 → 24, binds
## 10 → 7, body hits 71 → 55, pokes 18 → 9, criticals 1 → 1, kills 6 → 5,
## rounds 6 → 6, ring-outs 0 → 1.
##
## Rules 32 review (rules 31 → 32) — the frictionless emergent-contact
## checkpoint (7B.5B-0, EMERGENT-COMBAT-001). Three changes, one version.
## (1) The scripted bind is deleted as a physics source: there is no `BIND`
## phase, no `bind_started` event, no plant/squareness winner and no speed
## zeroing. A bind is now only a reading of a contact that persists — hence
## `bind_started` leaves the counted metrics entirely. (2) One arrest law for
## a first impact and a held contact (RIGID-CONTACT-002): a hold ends a cut
## only when it opposed it (`Δθ̇·dir < 0`) and left it no longer progressing
## (`θ̇·dir ≤ 0`) — no ratio, no `deflect_fraction`, no timer. A contact that
## merely slows a cut no longer ends it, so met cuts carry through more often.
## (3) Single velocity ownership in the solver (the dead swing-arrest fields
## `swing_stop_base/scale`, `swing_end_impulse` are gone). Played old law
## beside new: each duel is identical up to the first divergence the change
## produces, then diverges; the four seeds' first divergences each trace to
## one of the three changes (BIND removal, the arrest law, body-row velocity
## ownership), never an unintended side effect. Golden totals v31 → v32:
## attacks 96 → 89, blade collisions 87 → 62, parries 24 → 6, binds 7 → 0,
## body hits 55 → 71, pokes 9 → 13, criticals 1 → 2, kills 5 → 7, rounds
## 6 → 7, ring-outs 1 → 0. On the 40-seed feel corpus (Medium vs Hard): binds
## 0, clashes 2302, hits 2298, kills 125, damage 21751; only 350 of 806 met
## swinging swords (43%) are interrupted at the clash, down from v31's ~86%.
## Known frictionless artefact this checkpoint deliberately exposes: a cut
## resting on a torso slides along it with no friction to arrest it (626
## episodes, 183 ≥ 10 ticks, longest 41) — Coulomb friction (7B.5B) is the
## conventional fix, not a new feel force. Read the totals, not per seed.
##
## Rules 33 review (rules 32 → 33) — mass truth. Translational contact rows
## use the fighter's real mass, and passive weapon inertia is the sword plus
## the hands at the grip. Plant and commitment no longer scale that inertia
## (the coupling floor and commit bonus are deleted; the speed guardrail uses
## the sword's centroidal inertia alone). Nothing here is a new force. The
## same impulse now changes a body's velocity by J/m at ~80 kg instead of a
## lighter coupled mass, so duels shove less and the chaotic seeds diverge.
## Golden totals v32 → v33: attacks 89 → 95, blade collisions 62 → 67,
## parries 6 → 11, body hits 71 → 56, pokes 13 → 5, criticals 2 → 1, kills
## 7 → 6, rounds 7 → 6, ring-outs 0 → 0. Seed 5 no longer finishes a round
## inside the window (1 kill and 6 hits → none): the heavier body is not
## walked into a kill by the old shove. The representative ship corpus still
## reports zero solver fallbacks. No golden duel faulted. Read the totals.
##
## Rules 34 review (rules 33 → 34) — Coulomb friction (BLADE-FRICTION-001) on
## first clashes and on every held row (blade 0.20, blade on a body 0.05),
## four fixed iterations, warm start from the same feature (RIGID-CONTACT-003),
## a speculative guard-stop row in the held block, and the re-hold line taken
## one slop below where a sweep begins. Golden totals v33 → v34: attacks
## 95 → 89, blade collisions 67 → 61, parries 11 → 7, body hits 56 → 59, pokes
## 5 → 4, criticals 1 → 2, kills 6 → 6, rounds 6 → 6, ring-outs 0 → 0. The
## behaviour diff is read on the 40-duel CPU corpus (`feel_report`) against a
## μ = 0 control on the same code: clashes 2102 → 2386, a clash turns into a
## body hit within 0.5 s less often (16.7 % → 14.9 %), kills 123 → 123,
## damage flat, sword-on-torso contacts still all slides (no STALL), and the
## p90 body Δv at a clash 2.7 → 3.7 m/s — a sword pinned at its stop can no
## longer turn away, so the bodies take that impulse. Ship corpus zero
## fallbacks; passivity audit green with friction on.
##
## Rules 35 review (rules 34 → 35) — the whole sword is solid. The crossguard
## (the model's 28.8 cm bar, 2.5 cm deep) and the handle (the model's grip,
## 1.5 cm radius — never the fists) collide like the blade, and one sword pair
## keeps up to two contact points chosen the same way for every feature pair
## (a line contact's two ends; a blade on the handle and on the other blade; a
## blade in the corner of crossbar and handle), solved together from the first
## impact. Golden totals v34 → v35: attacks 89 → 108, blade collisions
## 61 → 89, parries 7 → 15, body hits 59 → 36, pokes 4 → 6, criticals 2 → 3,
## kills 6 → 5, rounds 6 → 5, ring-outs 0 → 0. On the 40-duel CPU corpus
## (`feel_report`): clashes 2386 → 3779, hits 1810 → 1362, kills 123 → 106,
## damage 22728 → 20175, whiffs 1441 → 1097, a clash turns into a body hit
## within 0.5 s more often (14.9 % → 18.9 %). The crossbar and handle catch cuts
## that used to slip past the blade into the torso — the hilt-end wedge this
## stage exists to close — so there are more contacts and fewer, later hits.
## Ship corpus zero fallbacks, zero centreline crossings, zero turn guards;
## passivity audit green. Read the totals, not per seed.
##
## Rules 35 close-out (still rules 35; uncommitted, so no version bump) —
## three corrections, no new force: (1) contact identity is geometric
## (CONTACT-IDENTITY-001) — a surviving line-contact end warm-starts from its
## own record, never slot 0's — and identity (ids, ages, feature coordinates)
## is hashed; (2) a frictional first impact ends with a normal-only top-up so
## every row meets its restitution target (one or two points); (3) the clash
## energy is the solve's kinetic-energy drop (payload only, not hashed).
## Seed 9's metrics are unchanged (its hash moved only by the new hashed
## identity); seeds 3, 5 and 17 diverge through two-point contacts. Golden
## totals: attacks 108 → 102, blade collisions 89 → 87, parries 15 → 14, body
## hits 36 → 43, pokes 6 → 5, criticals 3 → 4, kills 5 → 5, rounds 5 → 5,
## ring-outs 0 → 0. Read the totals, not per seed.
##
## Rules 36 review (rules 35 → 36) — mirrored commitment, physical whiff,
## exposure as a reading. Commitment is one continuous reading of the swing
## (it builds with physical travel and blade speed, no phase steps, no side);
## exposure is how far behind in time-to-threat a fighter is and no longer
## scales damage, stagger or criticals; the CPU's opening input is that
## reading. Golden totals v35 → v36: attacks 102 → 103, blade collisions
## 87 → 95, parries 14 → 14, body hits 43 → 52, pokes 5 → 6, criticals 4 → 3,
## kills 5 → 5, rounds 5 → 5, ring-outs 0 → 0. 40-duel CPU corpus: attacks
## 3412 → 4114, clashes 3779 → 4441, hits 1244 → 1377, kills 102 → 101,
## damage 18653 → 19370 (per hit 15.0 → 14.1: no exposure multiplier), whiffs
## 1063 → 1191, rounds 21.2 → 24.3 s. CPU weights untouched (7B.8).
##
## Rules 37 review (rules 36 → 37) — one two-point manifold per feature pair.
## The whole sword pair used to be capped at two points, so a hilt lock's
## third independent constraint was dropped and the position stage cleared
## the slip; now every feature pair keeps its own points and every one is a
## row of one exact block. A near-parallel line contact is always held at both
## ends (it could be held at an interior point and one end, the other free to
## turn in). One- and two-row blocks solve bit-identically. Seed 9's metrics are
## unchanged (its hash moved only by the hash layout: hold count plus entries).
## Golden totals v36 → v37: attacks 103 → 105, blade collisions 95 → 89,
## parries 14 → 13, body hits 52 → 50, pokes 6 → 4, criticals 3 → 3, kills
## 5 → 4, rounds 5 → 4, ring-outs 0 → 0. 40-duel CPU corpus: attacks
## 4114 → 3806, clashes 4441 → 4211, hits 1377 → 1262, kills 101 → 96, damage
## 19370 → 17229, whiffs 1191 → 1111, rounds 24.3 → 23.9 s; 4.2 % of held ticks
## carry more than two rows (at most six points); meaningful contacts dropped
## 0, pivot caps 0. Locks that used to lose a constraint now hold, so slightly
## fewer cuts slip through. CPU weights untouched (7B.8).
##
## Rules 38 review (rules 37 → 38) — the round's winner keeps control through
## the result, not only the post-round freedom, until exactly the next intro
## or the match end (`DuelSimulation.accepts_gameplay_input`). Only the
## pilots' swings during the result changed: attacks released 105 → 110
## (seed 3 +1, seed 9 +1, seed 17 +3, seed 5 none); every other count and all
## four final hashes are unchanged, because the round reset at the end of the
## result clears what those swings did.
##
## Rules 39 review (rules 38 → 39) — a killed body is a body: thrown along the
## killing impulse, lying after its collapse, pushed and turned by the contact
## impulse, sliding on ground friction, carried over the edge without touching
## the result (FallenBodySystem). Every golden combat metric is unchanged; the
## four final hashes moved only because each fighter's body state is now
## hashed.
##
## Rules 40 review (rules 39 → 40) — the hilt track narrows into a
## forward-biased, mirrored teardrop (SLASH-SHAPE-001): Long Guard unchanged,
## Ready/Gather/Load drawn in toward the centreline (lateral 0.13/0.18/0.20 →
## 0.08/0.13/0.16 m; the load 3 cm deeper, which is what clears its crossguard
## off the chest). Strike reach is unchanged, so measure play is the same;
## what moved is the outside of the swing. Resting guards now ride closer
## together and meet sooner on an approach, and a loaded hilt covers its
## wielder's centreline, so more cuts are met by a sword (clashes 89 → 97,
## parries 13 → 14) and fewer points reach a body (pokes 4 → 2). Cuts that do
## land land cleaner: body hits 50 → 46, criticals 3 → 7, kills 4 → 6, rounds
## 4 → 6 (seed 5 now ends its round). Attacks 110 → 101, ring-outs 0 → 0. No
## golden duel faulted. 40-duel CPU corpus v39 → v40: attacks 3935 → 3264,
## whiffs 1224 → 856, clashes 4153 → 4091, hits 1557 → 1440, kills 139 → 125,
## damage 24064 → 22499, rounds 21.2 → 19.9 s; whiff → counter within 0.5 s
## 3.1 → 4.9 %, first-hit round wins 59.0 → 56.2 %; held ticks 48.9k → 58.5k
## (blade on crossguard 23.6k → 42.4k: resting guards ride closer); drops 0,
## pivot caps 0, torso STALL 3 → 2.
##
## Rules 41 review (rules 40 → 41) — UNIFIED-MASS-001: the motor divides its
## torque by the weapon coordinate's held generalized inertia at the pose (the
## hilt track's motion and the hands included), the same `M_θ` every contact
## uses, instead of the sword's bare moment; torques untouched, so every
## motor phase is slower by the hands' and the track's share. Plus one loop
## rule found by the ship corpus (seed 117, a corpse's crossguard turning at
## 10 rad/s): a re-hold that finds nothing closing hands the rest of the
## tick's drift to the position stage (RIGID-CONTACT-001) — no golden metric
## moved by it. Golden totals: attacks 101 → 108, clashes 97 → 100, parries
## 14 → 13, body hits 46 → 69, pokes 2 → 4, criticals 7 → 3, kills 6 → 5,
## rounds 6 → 5, ring-outs 0 → 0. Seed 9 carries the rise (hits 10 → 33): its
## wandering pilots clinch at close range and the slower-settling blades lay
## their fortes on each other's torsos, one light hit per real entry (most
## 0.1–2 damage, often both fighters on the same tick) — the entry lifecycle
## gates every one; nothing multi-hits. No golden duel faulted. 40-duel CPU
## corpus v40 → v41: attacks 3264 → 3601, clashes 4091 → 4543, hits
## 1440 → 1558, kills 125 → 120, damage 22499 → 22653, whiffs 856 → 897,
## rounds 19.9 → 20.7 s; whiff → counter 4.9 → 4.7 %, first-hit round wins
## 56.2 → 56.1 %; peak tip speeds unchanged (the ceilings did not move, only
## the time to reach them); drops 0, pivot caps 0, ship-corpus re-hold
## exhaustions 0.
##
## Rules 42 review (rules 41 → 42) — Wolf calibration plus a determinism fix.
## A full charge targets 18 rad/s (was 20; the charge mix stays linear, so a
## half charge is 14.25). The injury calibration is pinned to its rules-39
## values, now authored as named, unit-bearing constants
## (`REFERENCE_STAGGER_IMPULSE_NS` / `REFERENCE_CUT_ENERGY_J` /
## `REFERENCE_THRUST_ENERGY_J`), so the slower full cut delivers less rather
## than being renormalized. One side asymmetry the FUZZ growth oracle caught
## (seed 23 tick 566: the gap stepped from 6e-15 to 9e-2): the footwork's
## brake-or-drive choice read an exact sign of a velocity residue of a few
## ulps, so one side of a mirror braked from rest and the other drove; it now
## reads both its tests to within `MovementSystem.SPEED_TIE`. Seed 9's body
## hits settle from the v41 clinch high back to 19, each a genuine re-entry
## past the 4.4 cm hysteresis (COMBAT-007; the lifecycle gates every one).
##
## Rules 45 review (rules 42 → 45), attributed one version at a time on these
## four seeds (the wander pilots never read the threat predictor):
## - 42G (generic combatants): hashes bit-identical to rules 42.
## - v43 (threat from the swept blade): hashes bit-identical again; only the
##   PARRY counts move (3: 1→0, 9: 4→2, 17: 5→2) — threat is a label and
##   reaches no physics.
## - v44 (physical recovery): time in recovery falls about threefold (seed 3:
##   352/191 → 108/124 ticks; seed 5: 404/329 → 129/156). Under the authored
##   recovery timer most wander hits landed on an opponent still stuck in it —
##   the hidden whiff penalty this version removed — so with the guard back
##   under control they meet it as clashes (3: hits 22→1; 5: 16→0). Wander
##   pilots take no angles, so nothing else opens a line for them.
## - v45 (condition): fatigue no longer scales the motors (STAMINA-002), so
##   the fights drift apart from the first exertion (5: hits 0→10).
## - v45 close: PARRY is physical interception (PARRY-001) and a cut pinned
##   under control speed is arrested (RIGID-CONTACT-002). Cuts that crept
##   through a resting guard into a hit, or overswung and read as a false whiff,
##   are now arrested parries (5: hits 9→0, whiffs 10→3, parries 7→18).
##
## Rules 46 review (rules 45 → 46): one law changed — turn authority is now
## `lerp(1, min_tracking, C_eff)` of the directional commitment (weapon and
## forward stopping times) instead of the authored K, overswing and
## counter-rotation terms. A tap or a walk now costs little heading, a full cut
## at speed nearly all of it. Seeds 3, 5 and 9 move by a few clashes and
## parries; seed 17's attacks keep tracking onto the target instead of meeting
## its guard (clashes 22→17, hits 7→20).
##
## Rules 46 revision: three order-independence corrections (FRICTION-ORDER-001:
## footwork reads the opponent at the start of the tick, friction rows step
## together, overlap ends are the bounding endpoints) and commitment rebuilt as
## redirect debt (momentum plus committed drive over 0.1 s against the brake;
## separate turn-torque and turn-rate floors). Every duel re-rolls from the first
## asymmetric press; the totals stay in the same band (3: hits 1→1; 5: 0→3;
## 9: 21→26; 17: 20→10). The soft-start revision (smooth debt against healthy
## brakes, curves 0.35 / 0.50 with floors 0.25 / 0.40) leaves every metric
## unchanged; only seed 3's final state moves.
##
## Rules 47 revision: footwork in the combat frame (MOVEMENT-FRAME-001) — the
## feet drive down the heading, which the bearing only turns. A committed
## fighter no longer steers its body onto a target that has left its line, so
## off-line positions pay: landed hits rise and clashes fall where the CPUs
## circle (3: hits 1→7, clashes 45→28; 5: 3→9; 17: 10→17), and seed 9, a
## straighter duel, barely moves (hits 26→24).
##
## Rules 49 review (rules 47 → 49), attributed in two stages on these seeds by
## replaying the shipped tree with the rules-49 injury re-seed undone (the
## reference strike back to one reference-quality wound); the wander pilots
## never read the threat predictor, so its side fix moves nothing here.
## - 47 → 48 (one bundle): the inclusive guard stop (SYM-STORM-SEPARATING-001),
##   the per-row stop lock removed from two-point holds, stamina removed (a
##   state-layout change: every hash moves, no metric does) and V48A (the
##   handle collides but no longer protects; hands are wound-only discs).
##   Seed 9 is physically the same duel — every count but one is unchanged —
##   and its parries fall 4 → 1: those were cuts stopped on the handle, a
##   contact that is no longer a defence (DEFENSE-ROLE-001; the label moved,
##   the physics did not). Seeds 3, 5 and 17 re-roll from the first tick the
##   stop or the hands touch: 3: clashes 28→42, parries 6→9, hits 7→1;
##   5: clashes 42→37, hits 9→6; 17: about level (hits 17→16).
## - 48 → 49 (the knife-edge re-seed, REFERENCE_STRIKE_SEVERITY = 2): fights
##   end sooner and cuts land harder. 3: unchanged counts (one light hit; only
##   the hash moves); 5: its first kill (hits 6→4, round 1 ends); 9: kills
##   1→2, criticals 0→2, hits 24→12; 17: criticals 1→4, hits 16→6, the same
##   two kills sooner. No golden duel faulted.
##
## Rules 49 re-hold refinement and contact readings (reviews 13–14), attributed
## in two stages:
## - The re-hold crossing refinement (RIGID-CONTACT-001: a lone held pair is
##   re-held where it crossed its line, not at the substep's end). Seed 3's
##   long crossguard lock no longer sinks a substep past the line between
##   re-holds, so the duel takes another path from that bind: clashes 42→11,
##   parries 9→0, hits 1→6, its first kill. 9: criticals 2→1; 17: one attack,
##   one parry fewer, one clash more. 5 is physically unchanged.
## - ContactOutcome, DEFLECTION and state layout 4 (`deflection_pending`):
##   readings only — every count above is the same with them; every hash moves
##   with the layout; `deflection` joins the counts (seed 9: one).
##
## Rules 50 (blade-only steel; the crossguard passes through, the hands and
## handle are the grip region; state layout 5), attributed by tracing both
## builds tick by tick: every duel is identical until the first contact on
## crossguard or handle steel, and diverges exactly there —
## - 3: tick 119, a blade on the handle (rules 49 steel) is a grip wound on
##   the handle, then the torso;
## - 5: tick 125, a held blade contact that slid onto both crossguards cannot
##   (no event that tick); grip wounds follow two ticks later;
## - 9: tick 128, a blade on the handle is a grip wound, then the torso and a
##   kill;
## - 17: tick 126, a crossguard-on-crossguard clash is nothing — both pass
##   through.
## `body_hit` now counts grip wounds too. Golden totals v49 → v50: attacks
## 141 → 108, blade collisions 96 → 63, parries 10 → 16, deflections 1 → 3,
## body hits 28 → 91, pokes 2 → 5, criticals 5 → 5, kills 6 → 8, rounds
## 6 → 8, ring-outs 0 → 0. No golden duel faulted.
##
## Rules 51 (the attack track's slope is the derivative of the carriage it
## interpolates, BLADE-COLLISION-PARITY-001): traced tick by tick against
## rules 50, every duel is identical until its first attack release (3: tick
## 114, 5: 91, 9: 121, 17: 115), where only the swinging sword's θ and θ̇
## differ, in the sixth or seventh digit — the track's slope feeds the weapon's
## generalized inertia and lever. Bodies, headings, health and events are
## identical on that tick. Every count below is unchanged; only the hashes
## moved.
##
## Rules 52 (each crossguard protects its blade side: two guard-root steel
## pairs beside blade on blade, the root a shallow wedge standing out at most
## the bar's half-depth and the blade capsule starting at its apex, just above
## the drawn guard; state layout 6 hashes each pair's latch and every point's
## pair), attributed by tracing both builds tick by tick on physical state (the
## layouts differ, so hashes cannot be compared): every duel is identical
## until its first steel the new topology reads differently, and diverges
## exactly there —
## - 3: tick 259, 9: tick 493 and 17: tick 688, the same blade-on-blade
##   contact rules 51 met at fighter 0's blade base (fraction 0), now at the
##   blade's new start (fraction 0.009), so it solves a little differently
##   (17's is a parry either way);
## - 5: tick 125, inside a held one-point blade contact a guard root meets
##   the other blade from its protected side and joins as steel.
## Two earlier rules-52 candidates were re-pinned and then superseded: one kept
## a protected guard steel after its blade had slipped round the quillon (the
## ship corpus caught a degenerate pin against the bar's underside), and one
## had a root rising half its half-span, standing out 5.4 cm beyond the drawn
## sword. Golden totals v51 → v52: attacks 108 → 107, blade collisions
## 63 → 47, parries 16 → 9, deflections 3 → 1, body hits 91 → 97, pokes
## 5 → 7, criticals 5 → 7, kills 8 → 11, rounds 8 → 10, ring-outs 0 → 0 —
## the duels re-roll from their divergence and resolve sooner (3: four kills
## in three rounds; 9 and 17: a third round each). No golden duel faulted.
##
## Rules 53 (stamina, STAMINA-004; state layout 7 hashes it), attributed
## against the same duels with stamina neutral (`DuelFixture.stamina_neutral`:
## every cost zero, so s stays exactly 1 and the motors are rules 52's): the
## neutral run reproduces every rules-52 metric below exactly, on all four
## seeds, and the standard run leaves it on tick 74 in every seed — the
## second live tick, the first whose starting stamina is under 1 (0.9995
## after the first tick's footwork), so the first fatigue term below the
## identity; no dash, no gate. Golden totals v52 → v53: attacks 107 → 103,
## blade collisions 47 → 77, parries 9 → 11, deflections 1 → 2, body hits
## 97 → 99, pokes 7 → 11, criticals 7 → 6, kills 11 → 10, rounds 10 → 10,
## ring-outs 0 → 0 — the duels re-roll from the divergence; slightly weaker
## drives meet steel more often for the same round flow. No golden duel
## faulted.
##
## Rules 54 (guard return and soft limit, GUARD-RETURN-001,
## GUARD-LIMIT-SOFT-001; layout unchanged). Traced on the live state: every
## duel matches rules 53 until the first tick a coasting blade is off its
## committed guard, or a blade is already inside the soft zone —
## - 3: tick 159, a coasting blade off its guard (the zone is not entered
##   until 339);
## - 5: tick 127, a blade already inside the soft zone (the return follows
##   at 130);
## - 9: tick 129 and 17: tick 124, a coasting blade off its guard.
## Before those ticks the pose error is zero and the zone force is zero, so
## the motor is the old hold. Golden totals v53 → v54: attacks 103 → 116,
## blade collisions 77 → 89, parries 11 → 14, deflections 2 → 2, body hits
## 99 → 92, pokes 11 → 4, criticals 6 → 3, kills 10 → 8, rounds 10 → 7,
## ring-outs 0 → 0 — the duels re-roll from that tick (seed 5 finishes no
## round in the window). Hard-stop fallbacks in the window: 0, 30, 11, 3.
## A wind-up already resting on the stop adds none. No golden duel faulted.
##
## Mirrored headings (still rules 54, WEAPON-ORBIT-004): a negative heading's
## sine and cosine are the negation of the heading half a turn away, facing
## steps compose through that pair, and the world blade is the heading's
## rotation of `(cos θ, sin θ)`. Traced against the guard-return pin this
## paragraph replaces: position, velocity, weapon angle, weapon speed and stamina match
## through the opening. The hash already differs at tick 1 because the south
## heading's opening frame stores cosine −0 where the fold stored +0
## (`duel_forward` is hashed). The first body-velocity ulp is tick 78, 77, 76
## and 78. θ then stays on the odd series, so a left guard is the reflection
## of the right; that correction moves the hashes once more. Every combat
## metric below is unchanged either way; only the hashes moved.
##
## Stamina reference width (still rules 54), traced, not inferred from counts.
## The same current stop write, with the three references quantized back
## through Vector3, reproduces the previous pin on every seed
## (3 `74fd5ffa…`, 5 `503fcdd1…`, 9 `edd2ec7b…`, 17 `2763a48f…`).
## The float64 run is this pin. All four seeds first differ at tick 74, slot 0
## stamina, by 1.582e-14 (wide minus narrow: 0.9995426819755 vs
## 0.99954268195968 on seed 3; the other seeds differ by the same delta).
## Position, velocity, heading, health, weapon angle, weapon speed and phase
## still match on that tick. The reference deltas are move +2.44140625e-5,
## turn +4.27246094e-7, swing −7.17078e-7. The hash move is that stamina
## difference. The stop rewrite did not move these duels: the same stop
## functions with the references quantized reproduce those previous pins.
##
## Explicit drives (still rules 54). `base_drive` is torque times the damage
## term and `fatigue_scaled_drive` is `base_drive` times fatigue, instead of
## dividing the product back by fatigue. Against that divided form, seeds 5
## and 17 never differ. Seed 3 first differs at tick 1449 and seed 9 at tick
## 1356. At both ticks the printed angle, speed, stamina and motor torque
## match the divided form, and seed 9's combat counts do not move, so the
## hash is some other hashed field below that printing. Seed 9's final hash
## is the one re-pinned here. Seeds 3, 5 and 17 keep the reference-width pin.
## No golden duel faulted.
##
## Rules 57 (impact authority recovers, IMPACT-AUTHORITY-001; layout 9).
## Forcing the dip off reproduces the rules-55 per-seed table: seed 3 is
## 30 attacks, 29 blade collisions, 2 parries, 1 deflection, 27 body hits,
## 4 pokes, 1 kill and 1 round; seed 5 is 28, 25, 3, 0, 14, 3, 2 kills and
## 2 rounds; seed 9 is 31, 32, 5, 2, 10, 0, 1 kill and 1 round; seed 17 is
## 18, 13, 3, 0, 15, 1, 3 kills and 3 rounds. The numbers in the pin are
## the recovering duels. They are not a verdict that the fights are better.
## The first event one duel has and the other lacks is named on the hash
## pin. Corpus totals, rules 55 → 57, on these four seeds: attacks 107 →
## 120, blade collisions 99 → 101, parries 13 → 17, deflections 3 → 0,
## body hits 66 → 77, pokes 8 → 11, criticals 4 → 6, kills 7 → 6, rounds
## 7 → 6. Rules 56, which left authority on the floor, had moved the same
## window to 73 blade collisions and 7 parries. Recovery puts that steel
## play back. No golden duel faulted.
##
## Rules 58 (mutual hilt start-caps are not steel). Seed 3 does not move.
## Seeds 5, 9 and 17 re-roll from the first time both hilts sit in each
## other's start cap. Corpus totals on these four seeds, rules 57 → 58:
## attacks 109 → 124, blade collisions 98 → 125, parries 14 → 21,
## deflections 1 → 2, body hits 73 → 63, pokes 11 → 8, criticals 7 → 7,
## kills 7 → 5, rounds 7 → 5. Seed 5 loses a kill and a round (2/2 → 1/1).
## Seed 17 loses a kill and a round (2/2 → 1/1) and its body hits fall
## 30 → 17. Seed 9 keeps its kill, its round and its criticals. This is the
## hilt filter, not a retune. The first tick of each divergence was not
## isolated, so these pins record the new trace. They are not a verdict
## that the lost kills were false contacts. No golden duel faulted.
##
## Guard-stop arrival (still rules 57, GUARD-LIMIT-SOFT-001). `turned >= limit`
## kept outward speed when the same step's mirror, or the step itself, landed
## up to 1e-9 rad short. `STOP_ARRIVAL_RAD = 0` reproduces the previous final
## hashes, including seed 5 `879e861a…` and seed 9 `e2e7cd97…`. With the band,
## the wander tick-hash series first differs at step 209 on seed 5 and step
## 640 on seed 9 (0-based steps of the 1800-tick wander, intro included;
## `state.tick` after the step is one higher, and event ticks are the step).
## Seeds 3 and 17 do not move.
##
## Seed 5, step 209. Every hashed field was compared, bit for bit. The only
## difference is slot 0 speed: 0 with the band, −0.089244 rad/s without it.
## Angle −2.356194489299 on both, 8.93e-10 rad inside the negative limit,
## phase RECOVERY, torque 9.679. The previous step is `attack_released`.
## Writer: `stopped_speed` inside `assign_stop`, during the weapon step.
## Step 210: the motor records torque 8.439 against 8.607, because torque is
## `I·(ω' − ω) / dt` and ω was the stopped speed (`WeaponSystem._drive_motor`).
## End speeds differ by 4.7e-13. The swords are in a hold, so the warm-start
## impulses differ by about 4e-12 and both bodies' positions by less than
## 1e-15 m. Stamina bits match. Step 211's largest gap is still that hold
## impulse, a few trillionths. Nothing reconverges to the same bits. The
## first combat-event split is `blade_collision` at event tick 495 without the
## band and 496 with it: that contact, accumulated, not a second rule. Peak
## |ω| on the band run is 20.87 rad/s. `ccd_cap_hits` is 0.
##
## Seed 9, step 640. The only hashed difference is slot 0 speed: 0 with the
## band, +0.014285 rad/s without it. Stored angle 2.355897594245 on both,
## 0.30 mrad inside the limit, phase NEUTRAL, torque −7.869. The step before
## is outward at +0.496 rad/s and 0.238 mrad inside the limit, one tick of
## the speed the strict run keeps. A later writer in the same tick sets both
## angles and leaves the speed the stop wrote. Step 641: torque −7.231 against
## −7.254, and stamina 0.972532752 against 0.972533407. Stamina is
## `_measure_blade_work`: torque times the mid-step speed, settled by
## `StaminaModel`. That gap scales the next force, so step 642's acceleration
## differs by about 5e-6 m/s² and position by about 1e-9 m. The first
## combat-event split is `attack_started` at event tick 944 with the band and
## 941 without it; the strict run then has a `blade_collision` at 956. Peak
## |ω| on the band run is 25.81 rad/s. `ccd_cap_hits` is 0.
##
## Both first fields are the outward speed the band removes. The pins below
## are those duels continued, not a claim that the fighting improved. 1e-9
## stays; it was not narrowed to recover the old hashes.
func test_golden_combat_metrics_are_pinned() -> void:
	var golden := {
		3: {"attack_released": 26, "blade_collision": 19, "parry": 4, "deflection": 0, "body_hit": 22, "body_poke": 4, "body_thrust": 0, "critical_hit": 2, "fighter_killed": 2, "ring_out": 0, "round_ended": 2},
		5: {"attack_released": 36, "blade_collision": 33, "parry": 7, "deflection": 0, "body_hit": 17, "body_poke": 2, "body_thrust": 0, "critical_hit": 1, "fighter_killed": 1, "ring_out": 0, "round_ended": 1},
		9: {"attack_released": 31, "blade_collision": 33, "parry": 2, "deflection": 1, "body_hit": 7, "body_poke": 1, "body_thrust": 0, "critical_hit": 3, "fighter_killed": 1, "ring_out": 0, "round_ended": 1},
		17: {"attack_released": 31, "blade_collision": 40, "parry": 8, "deflection": 1, "body_hit": 17, "body_poke": 1, "body_thrust": 0, "critical_hit": 1, "fighter_killed": 1, "ring_out": 0, "round_ended": 1},
	}
	for seed_value: int in [3, 5, 9, 17]:
		var runner := _played(seed_value)
		var metrics := CombatMetrics.of(runner)
		assert_true(int(metrics[String(DuelEventTypes.ATTACK_RELEASED)]) > 10, "precondition: seed %d fought" % seed_value)
		assert_eq(metrics, golden.get(seed_value, {}), "seed %d combat metrics are unchanged" % seed_value)
		assert_eq(runner.simulation.diagnostics.ccd_cap_hits, 0, "seed %d never asks the sweep for more substeps than the cap" % seed_value)


func test_hash_sees_the_smallest_change() -> void:
	var state := DuelFixture.state(DuelFixture.rules())
	var before := StateHasher.hash_state(state)
	state.fighter(1).weapon.angle += 1e-12
	assert_ne(StateHasher.hash_state(state), before, "one ulp-scale change alters the hash")


func test_random_play_never_breaks_state_invariants() -> void:
	var rules := DuelFixture.rules()
	var violations := PackedStringArray()
	var contacts := 0
	for seed_value: int in [1, 2, 3, 4]:
		var runner := SimRunner.create(rules, seed_value)
		var pilot_0 := Pilot.wander(seed_value, 31)
		var pilot_1 := Pilot.wander(seed_value, 47)
		for _tick in TICKS:
			if runner.state.is_finished():
				break
			var events := runner.simulation.step(runner.state, pilot_0.command(runner.state, 0), pilot_1.command(runner.state, 1))
			for event in events:
				if event.type == DuelEventTypes.BODY_HIT or event.type == DuelEventTypes.BLADE_CONTACT:
					contacts += 1
			_check(runner.state, rules, violations)
	assert_true(contacts > 10, "precondition: the fights made contact (%d)" % contacts)
	assert_eq(violations.size(), 0, "invariants held: %s" % ", ".join(violations.slice(0, 5)))


## Events are derived from commands + versioned rules: replaying the record
## through a fresh simulation regenerates exactly the same events.
func test_events_are_derived_from_commands() -> void:
	var runner := _played(7)
	var rules := DuelFixture.rules()
	var live_events := runner.events.duplicate()
	assert_true(live_events.size() > 20, "precondition: enough events to compare (%d)" % live_events.size())
	var replay_sim := DuelSimulation.create(rules)
	var replay_state := replay_sim.new_match(runner.record.seed_value)
	var replay_events: Array[DuelEvent] = []
	for index in runner.record.tick_count():
		replay_events.append_array(replay_sim.step(replay_state, runner.record.command_at(0, index), runner.record.command_at(1, index)))
	assert_eq(replay_events.size(), live_events.size(), "same event count")
	for i in replay_events.size():
		assert_eq(replay_events[i].type, live_events[i].type, "event %d type matches" % i)
		assert_eq(replay_events[i].tick, live_events[i].tick, "event %d tick matches" % i)
		assert_eq(replay_events[i].actor, live_events[i].actor, "event %d actor matches" % i)


## Surface gap between the two bodies (m): standing push circles, or a push
## circle against a lying body's capsule (FallenBodyState). A body off the
## platform meets nothing.
static func _body_gap(state: MatchState, rules: DuelRules) -> float:
	var a := state.fighter(0)
	var b := state.fighter(1)
	if a.is_falling or b.is_falling or a.fallen.over_edge or b.fallen.over_edge or (a.fallen.is_lying() and b.fallen.is_lying()):
		return INF
	if not a.fallen.is_lying() and not b.fallen.is_lying():
		return DuelGeometry.distance(a, b) - rules.combatant(0).fighter.push_radius * 2.0
	var body := a if a.fallen.is_lying() else b
	var standing := b if body == a else a
	var h := rules.combatant(0).fighter.lying_half_length
	var ux := SimMath.cosine(body.fallen.yaw)
	var uy := SimMath.sine(body.fallen.yaw)
	var t := SimMath.closest_param_on_segment(body.x - ux * h, body.y - uy * h, body.x + ux * h, body.y + uy * h, standing.x, standing.y)
	var along := (2.0 * t - 1.0) * h
	return SimMath.length(standing.x - body.x - ux * along, standing.y - body.y - uy * along) - rules.combatant(0).fighter.push_radius - rules.combatant(0).fighter.lying_radius


func _check(state: MatchState, rules: DuelRules, violations: PackedStringArray) -> void:
	for fighter in state.fighters:
		var w := fighter.weapon
		for value: float in [fighter.x, fighter.y, fighter.vx, fighter.vy, fighter.facing, fighter.turn_rate, w.angle, w.speed]:
			if not is_finite(value):
				violations.append("non-finite value at tick %d" % state.tick)
		if fighter.health < 0.0 or fighter.health > rules.combatant(0).fighter.max_health:
			violations.append("health out of range at tick %d" % state.tick)
		## The arena is open: standing near the edge is legal, but a living
		## fighter whose centre has crossed it must already be falling.
		if fighter.is_alive() and not fighter.is_falling and SimMath.length(fighter.x, fighter.y) > rules.platform_radius + 1e-9:
			violations.append("left the arena without falling at tick %d" % state.tick)
		if absf(w.angle) > rules.combatant(0).weapon.guard_limit + 1e-12:
			violations.append("blade beyond guard at tick %d" % state.tick)
		if w.charge < 0.0 or w.charge > 1.0:
			violations.append("charge out of range at tick %d" % state.tick)
	if _body_gap(state, rules) < -1e-9:
		violations.append("bodies overlap at tick %d" % state.tick)
