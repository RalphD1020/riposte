extends TestCase

## SYM: the duel has no slot bias. The canonical setup is point-symmetric
## (180° rotation about the arena center), so a mirrored script must produce
## the mirrored outcome.
##
## See also: /docs/concepts/simulation.md


func _init() -> void:
	suite_name = "SYM"


## Where the scripted tap fires, as a share of the strike reach: far enough
## out that the tap clashes the opponent's resting guard and still lands.
## Closer in (0.70–0.85 at rules 45) the resting guard arrests the tap — a
## parry, under the one arrest law — and there is no hit to mirror.
const TAP_MEASURE_SHARE := 0.9


func _scenario(attacker: int) -> SimRunner:
	var rules := DuelFixture.rules()
	var runner := SimRunner.create(rules, 1)
	var pilots: Array[Pilot] = [Pilot.idle(), Pilot.idle()]
	pilots[attacker] = Pilot.approach_and_tap(WeaponKinematics.strike_reach(rules.combatant(0), rules.combatant(1)) * TAP_MEASURE_SHARE)
	runner.run(pilots[0], pilots[1], 260)
	return runner


func test_mirrored_attacks_produce_mirrored_outcomes() -> void:
	var left := _scenario(0)
	var right := _scenario(1)
	var left_hit := left.first(DuelEventTypes.BODY_HIT)
	var right_hit := right.first(DuelEventTypes.BODY_HIT)
	assert_true(left_hit != null and right_hit != null, "both scripted taps land")
	if left_hit == null or right_hit == null:
		return
	## Self-validating preconditions (the measure share is fixture setup, never
	## a gameplay invariant): both scenarios reach the same interaction by the
	## same route — the same tap, the same blade contacts before the hit, of the
	## same feature pairs, and no body collision contaminating it.
	assert_eq(left.count(DuelEventTypes.ATTACK_RELEASED), 1, "fixture: one tap in the left scenario")
	assert_eq(right.count(DuelEventTypes.ATTACK_RELEASED), 1, "fixture: one tap in the right scenario")
	assert_eq(_before(left, DuelEventTypes.BODY_PUSH, left_hit.tick).size(), 0, "fixture: no body collision precedes the left hit")
	assert_eq(_before(right, DuelEventTypes.BODY_PUSH, right_hit.tick).size(), 0, "fixture: nor the right one")
	var left_clashes := _before(left, DuelEventTypes.BLADE_CONTACT, left_hit.tick)
	var right_clashes := _before(right, DuelEventTypes.BLADE_CONTACT, right_hit.tick)
	assert_eq(right_clashes.size(), left_clashes.size(), "fixture: the same blade contacts on the way in")
	for i in mini(left_clashes.size(), right_clashes.size()):
		assert_eq(right_clashes[i].tick, left_clashes[i].tick, "fixture: clash %d on the same tick" % i)
		assert_eq(int(right_clashes[i].number(DuelEventKeys.FEATURE_0)), int(left_clashes[i].number(DuelEventKeys.FEATURE_1)), "fixture: clash %d on the mirrored feature pair" % i)
		assert_eq(int(right_clashes[i].number(DuelEventKeys.FEATURE_1)), int(left_clashes[i].number(DuelEventKeys.FEATURE_0)), "fixture: and its partner")
	assert_eq(left_hit.tick, right_hit.tick, "same tick")
	assert_eq(left_hit.actor, 0, "slot 0 struck in its scenario")
	assert_eq(right_hit.actor, 1, "slot 1 struck in its scenario")
	assert_near(left_hit.number(DuelEventKeys.DAMAGE), right_hit.number(DuelEventKeys.DAMAGE), 1e-6, "equal damage")
	assert_near(left.state.fighter(1).health, right.state.fighter(0).health, 1e-6, "equal remaining health")
	assert_near(left.state.fighter(0).x, -right.state.fighter(1).x, 1e-6, "point-reflected attacker position")
	assert_near(left.state.fighter(0).y, -right.state.fighter(1).y, 1e-6, "point-reflected attacker lateral position")


## `runner`'s events of `type` strictly before `tick`.
func _before(runner: SimRunner, type: StringName, tick: int) -> Array[DuelEvent]:
	var found: Array[DuelEvent] = []
	for event in DuelFixture.of_type(runner.events, type):
		if event.tick < tick:
			found.append(event)
	return found
