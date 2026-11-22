extends TestCase

## CHARGE-BOUNDARY: an angular charged cut earns power only from the outward
## wind-back its hold actually achieves (COMBAT-001, rules today). Characterizes,
## for both directions: the most charge available from each start angle (a blade
## nearer the ±135° stop has less to wind), a hold at the stop earning nothing,
## and a partial release launching with exactly the charge it earned — whose
## nominal sweep from the Ready guard ends at the opposite Ready guard (−45° →
## +45°). Simulation unchanged; these pin the current rule as a baseline.
##
## Not here: farming by shoves and refunds is `test_attack.gd`'s (a shove credits
## at most one tick of motor wind-back and never refunds); the central thrust
## sector's axial charge is W-THRUST, not implemented.
##
## See also: /docs/concepts/combat.md

## Start angles (degrees, the fighter's right side; each also run mirrored).
const STARTS := [-45.0, -70.0, -90.0, -115.0, -135.0]
## A hold long enough for the motor to reach the stop from any start.
const HOLD_TICKS := 120

var _rules: DuelRules


func _init() -> void:
	suite_name = "CHARGE-BOUNDARY"
	_rules = DuelFixture.rules()


## Press at `start` (degrees) and hold `ticks`; returns the rig still holding.
func _hold_from(start: float, ticks: int) -> WeaponRig:
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.reset(deg_to_rad(start))
	rig.press()
	rig.hold(ticks)
	return rig


## Press at `start` and hold until the earned charge reaches `target` (or the cap).
func _hold_until(start: float, target: float) -> WeaponRig:
	var rig := WeaponRig.create(_rules)
	rig.fighter.weapon.reset(deg_to_rad(start))
	rig.press()
	while rig.fighter.weapon.charge < target and rig.tick < HOLD_TICKS:
		rig.step()
	return rig


func test_the_charge_available_is_the_wind_back_left_before_the_stop() -> void:
	var weapon := _rules.combatant(0).weapon
	var limit := rad_to_deg(weapon.guard_limit)
	var span := rad_to_deg(weapon.windback_span())
	## ARRANGE: the reference sword's stop and the span that buys full charge.
	assert_near(limit, 135.0, 1e-6, "fixture: the domain stops at ±135°")
	assert_near(span, 90.0, 1e-6, "fixture: 90° of wind-back buys full charge")
	for side: float in [1.0, -1.0]:
		for start: float in STARTS:
			var from := start * side
			## ACT: hold until the blade has wound as far as it can.
			var rig := _hold_from(from, HOLD_TICKS)
			var held := rig.fighter.weapon
			## ASSERT: it wound to the stop on its own side, and the charge is what
			## that travel bought — never more for starting nearer the stop.
			assert_eq(held.phase, CombatPhase.Id.CHARGING, "fixture: %+.0f° still holding" % from)
			assert_near(rad_to_deg(held.angle), signf(from) * limit, 0.5, "from %+.0f° the hold winds to the stop" % from)
			var expected := clampf((limit - absf(start)) / span, 0.0, 1.0)
			assert_near(held.charge, expected, 0.005, "from %+.0f° the most charge is %.3f" % [from, expected])
	## PERTURB: a hold that starts inside the guard (−35°) first restores the blade
	## to the guard, which earns nothing, so full charge needs the whole way to
	## the stop (characterized: 100° of travel for 90° of credit).
	var inside := _hold_from(-35.0, HOLD_TICKS)
	assert_near(inside.fighter.weapon.charge, 1.0, 0.005, "from −35° the hold still earns full charge at the stop")
	var partway := _hold_until(-35.0, 0.0)
	while rad_to_deg(partway.fighter.weapon.angle) > -45.0 and partway.tick < HOLD_TICKS:
		partway.step()
	assert_true(partway.fighter.weapon.charge <= 0.02, "and the first 10° back to the guard is restoration, not charge (%.3f)" % partway.fighter.weapon.charge)


func test_a_hold_at_the_stop_earns_nothing_and_releases_a_quick_cut() -> void:
	var weapon := _rules.combatant(0).weapon
	for side: float in [1.0, -1.0]:
		## ARRANGE / ACT: pressed at the stop and held for a second.
		var rig := _hold_from(-135.0 * side, 60)
		var held := rig.fighter.weapon
		## ASSERT: no wind-back is possible, so no charge, however long the hold.
		assert_near(held.earned_windback, 0.0, 1e-12, "%+.0f°: a blade at the stop cannot wind back" % (-135.0 * side))
		assert_near(held.charge, 0.0, 1e-12, "%+.0f°: and holding there earns nothing" % (-135.0 * side))
		## PERTURB / ACT: release.
		rig.release()
		## ASSERT: the minimum (quick-cut) sweep toward the other side.
		assert_near(held.swing_charge, 0.0, 1e-12, "the release carries no charge")
		assert_near(rad_to_deg(absf(held.swing_end - held.swing_start)), rad_to_deg(weapon.arc(0.0)), 1e-6, "and commands the 90° quick cut")


func test_a_partial_release_uses_its_earned_charge_and_aims_at_the_opposite_ready() -> void:
	var weapon := _rules.combatant(0).weapon
	var ready := rad_to_deg(weapon.guard_angle)
	assert_near(ready, 45.0, 1e-6, "fixture: Wolf's Ready guard is ±45°")
	for side: float in [1.0, -1.0]:
		for target: float in [0.25, 0.5, 0.75, 1.0]:
			## ARRANGE: hold from Ready until the earned charge reaches the target.
			var rig := _hold_until(-ready * side, target)
			var earned := rig.fighter.weapon.charge
			assert_true(earned >= target - 1e-9, "fixture: %+.0f° earned %.2f" % [-ready * side, earned])
			## ACT: release now, wherever the wind-back reached.
			rig.release()
			var swing := rig.fighter.weapon
			## ASSERT: the cut carries exactly the charge it earned, its sweep is the
			## arc of that charge, and from Ready that sweep ends at the opposite
			## Ready guard — the nominal, unopposed objective (the blade's own
			## braking past it is RECOVERY-001's, characterized in QUICK-90).
			assert_near(swing.swing_charge, earned, 1e-12, "%+.0f° charge %.2f: the release uses the earned charge" % [-ready * side, target])
			assert_near(absf(swing.swing_end - swing.swing_start), weapon.arc(earned), 1e-9, "its commanded sweep is the arc of that charge")
			assert_near(rad_to_deg(swing.swing_end), ready * side, 1.0, "and from Ready it aims at the opposite Ready guard (%.2f°)" % rad_to_deg(swing.swing_end))
