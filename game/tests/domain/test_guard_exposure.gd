extends TestCase

## GUARD-EXPOSURE: guarding measured on the real simulation, never awarded.
## A reference attacker taps from ±45° into a defender whose blade is either
## held at θ (a test-only spec whose guard return targets |θ|: the ordinary
## bounded return motor, θ̇ = 0) or winding back through θ in a real charge.
## Outcome per scenario: flesh (a body hit landed), steel (the blades met and no
## hit landed) or miss. Static coverage `G = steel / (steel + flesh)`. A
## characterization with no target curve: the measured values are reported,
## and only the physical relations the design rests on are asserted.
##
## See also: /docs/concepts/combat.md

const DISTANCES := [1.25, 1.6]
const BEARINGS := [-20.0, 0.0, 20.0]
const ATTACKS := [-45.0, 45.0]
const STEEL := [DuelEventTypes.BLADE_CONTACT, DuelEventTypes.PARRY, DuelEventTypes.DEFLECTION]
const FLESH := [DuelEventTypes.BODY_HIT, DuelEventTypes.BODY_POKE]
const WINDOW_TICKS := 45


func _init() -> void:
	suite_name = "GUARD-EXPOSURE"


## The reference duelist and sword with the guard return holding the blade at
## |`hold`| degrees (test-only; no shipped content changes).
func _held_spec(hold: float) -> CombatantPhysicsSpec:
	var fighter := FighterCatalog.duelist()
	var weapon := WeaponCatalog.of(ContentIds.WEAPON_BASTARD_SWORD, fighter.grip_radius)
	weapon.guard_angle = minf(deg_to_rad(absf(hold)), weapon.guard_limit - 1e-3)
	weapon.precompute()
	return LoadoutCatalog.assemble(fighter, weapon)


func _scenario(hold: float, charging: bool, distance: float, bearing: float, attack: float) -> String:
	var standard := StandardDuelRules.create()
	var defender := standard.combatant(0) if charging else _held_spec(hold)
	var runner := SimRunner.create(DuelFixture.with_loadouts(standard.combatant(0), defender), 7)
	runner.skip_intro()
	var striker := runner.state.fighter(0)
	var target := runner.state.fighter(1)
	var b := deg_to_rad(bearing)
	DuelFixture.place(target, 0.0, 0.0, 0.0)
	DuelFixture.place(striker, distance * cos(b), distance * sin(b), atan2(-sin(b), -cos(b)))
	striker.weapon.reset(deg_to_rad(attack))
	target.weapon.reset(deg_to_rad(45.0 * signf(hold)) if charging else deg_to_rad(hold))
	if charging:
		## The defender winds back from its guard; the strike starts as it passes θ.
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, false))
		for _i in 120:
			if absf(target.weapon.angle) >= deg_to_rad(absf(hold)):
				break
			runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	var start := runner.events.size()
	runner.push(PlayerCommand.create(runner.state.tick, 0.0, 0.0, true, true), PlayerCommand.idle(runner.state.tick))
	for _i in WINDOW_TICKS:
		runner.push(PlayerCommand.idle(runner.state.tick), PlayerCommand.idle(runner.state.tick))
	assert_true(runner.is_sound(), "every scenario tick holds the invariants (%s)" % runner.violation_summary())
	var touched := false
	for index in range(start, runner.events.size()):
		var event: DuelEvent = runner.events[index]
		if FLESH.has(event.type):
			return "flesh"
		touched = touched or STEEL.has(event.type)
	return "steel" if touched else "miss"


func _sweep(hold: float, charging: bool) -> Dictionary:
	var tally := {"steel": 0, "flesh": 0, "miss": 0}
	for distance: float in DISTANCES:
		for bearing: float in BEARINGS:
			for attack: float in ATTACKS:
				tally[_scenario(hold, charging, distance, bearing, attack)] += 1
	var threats: int = tally["steel"] + tally["flesh"]
	tally["threats"] = threats
	tally["G"] = float(tally["steel"]) / float(threats) if threats > 0 else NAN
	tally["P_hit"] = float(tally["flesh"]) / float(threats) if threats > 0 else NAN
	return tally


func test_static_coverage_is_measured_on_the_real_solver_and_mirrors() -> void:
	## ARRANGE: the sample reaches the defender (a coverage over no threats is no measurement).
	var ready := _sweep(-45.0, false)
	assert_true(ready["threats"] >= 8, "fixture: the sampled taps reach the Ready defender (%d threats)" % ready["threats"])
	## ACT: Ready, gathered and fully wound, each held still; and the mirror.
	var gathered := _sweep(-80.0, false)
	var wound := _sweep(-135.0, false)
	var mirrored := _sweep(45.0, false)
	## ASSERT: the measurement is deterministic and the plane's mirror holds.
	assert_eq(_scenario(-45.0, false, 1.25, 0.0, -45.0), _scenario(-45.0, false, 1.25, 0.0, -45.0), "one scenario, one outcome")
	assert_eq(mirrored["steel"], ready["steel"], "the left Ready blocks what the right Ready blocks")
	assert_eq(mirrored["flesh"], ready["flesh"], "and lets through the same")
	## Reported, not targeted: a blade lying along the flank shields that flank and
	## leaves the other open, so aggregate static coverage need not fall with
	## the wind-back (weapons plan, GUARD-COVERAGE).
	for reading: Array in [["Ready -45", ready], ["gathered -80", gathered], ["wound -135", wound]]:
		var tally: Dictionary = reading[1]
		assert_true(tally["threats"] > 0, "%s: G = %.2f (%d steel / %d flesh / %d miss)" % [reading[0], tally["G"], tally["steel"], tally["flesh"], tally["miss"]])


func test_charging_through_an_angle_is_more_exposed_than_holding_it() -> void:
	## ARRANGE / ACT: the same body, sword, attacker and geometry; only the
	## defender's blade motion differs — still at -80° versus winding back through it.
	var held := _sweep(-80.0, false)
	var charging := _sweep(-80.0, true)
	assert_true(held["threats"] > 0 and charging["threats"] > 0, "fixture: both samples are threatened")
	## ASSERT: the receding blade with the charge's commitment lets more hits
	## through — the trade-off emerges from momentum, the suspended return and
	## commitment, with no exposure penalty anywhere in the rules.
	assert_true(charging["P_hit"] >= held["P_hit"], "charging at -80° is at least as exposed as holding there (P_hit %.2f vs %.2f)" % [charging["P_hit"], held["P_hit"]])
	assert_true(charging["P_hit"] > held["P_hit"], "and measurably more (ΔP_hit = %+.2f)" % (charging["P_hit"] - held["P_hit"]))
