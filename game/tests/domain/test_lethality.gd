extends TestCase

## LETHALITY: lethality law (COMBAT-010, COMBAT-011). One physical severity
## model for base evaluation; lethality diverges by classification. POKE at or
## above a severity threshold is lethal. THRUST (burst-aligned point entry) is
## always lethal — defense is determined by the chronological TOI solver, which
## redirects the weapon trajectory on blade contact before evaluating body
## contacts. There is no persisted defense flag. The base severity model is
## shared — there is no STAB_MULTIPLIER.
##
## Implements: /spec/invariants.md#combat-010, #combat-011
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "LETHAL"
	_rules = DuelFixture.rules()


## Helper: evaluate a point-strike at the blade tip with the given setup.
func _evaluate_tip(a: FighterState, b: FighterState) -> StrikeResult:
	var tip_x := a.x + _rules.weapon.tip_radius
	return DamageModel.evaluate(a, b, tip_x, 0.0, _rules)


## Helper: standard thrust pair at tip-touching distance.
func _pair(a_speed: float) -> Array:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, _rules.weapon.tip_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.swing_dir = 1.0
	a.weapon.angle = 0.0
	a.weapon.speed = 0.0
	a.vx = a_speed
	return [state, a, b]


func _make_thrust(a: FighterState) -> void:
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0


## --- Statistical lethality (COMBAT-011) --------------------------------------


func test_walking_speed_poke_is_survivable() -> void:
	## A poke at normal walking speed is below the lethal threshold.
	var data := _pair(3.0)
	var a: FighterState = data[1]
	var b: FighterState = data[2]
	var strike := _evaluate_tip(a, b)
	assert_eq(strike.contact_kind, StrikeResult.ContactKind.POKE, "classified as POKE")
	assert_false(strike.lethal, "walking-speed poke is below the lethal threshold")
	assert_true(strike.damage > 0.0, "but it still does damage")
	assert_true(strike.damage < _rules.fighter.max_health, "and is survivable")


func test_thrusts_statistically_more_lethal_than_pokes() -> void:
	## Unprotected thrusts are always lethal (COMBAT-011); pokes at walking
	## speeds are not. The lethality law amplifies the natural speed advantage.
	var poke_damage := 0.0
	var thrust_damage := 0.0
	var trials := 10
	for i in trials:
		var walk_speed := 2.0 + float(i) * 0.3
		var poke_data := _pair(walk_speed)
		var poke_a: FighterState = poke_data[1]
		var poke_b: FighterState = poke_data[2]
		var poke_strike := _evaluate_tip(poke_a, poke_b)
		poke_damage += poke_strike.damage
		var burst_speed := 7.0 + float(i) * 0.5
		var thrust_data := _pair(burst_speed)
		var thrust_a: FighterState = thrust_data[1]
		var thrust_b: FighterState = thrust_data[2]
		_make_thrust(thrust_a)
		var thrust_strike := _evaluate_tip(thrust_a, thrust_b)
		thrust_damage += thrust_strike.damage
	assert_true(thrust_damage > poke_damage, "thrusts (at burst speeds) deal more total damage than pokes (at walking speeds)")


func test_poke_can_be_lethal_at_high_speed() -> void:
	## COMBAT-011: a POKE at high axial severity triggers the lethal threshold.
	var data := _pair(12.0)
	var a: FighterState = data[1]
	var b: FighterState = data[2]
	b.vx = -4.0
	var strike := _evaluate_tip(a, b)
	assert_eq(strike.contact_kind, StrikeResult.ContactKind.POKE, "this is classified as a POKE")
	assert_true(strike.lethal, "high-speed poke exceeds the lethal severity threshold")
	assert_eq(strike.damage, _rules.fighter.max_health, "lethal poke deals max health damage")


func test_opponent_dashing_onto_point_is_lethal() -> void:
	## The opponent's own velocity contributes to severity (PHYS-001).
	var data := _pair(2.0)
	var a: FighterState = data[1]
	var b: FighterState = data[2]
	b.vx = -10.0
	var strike := _evaluate_tip(a, b)
	assert_eq(strike.contact_kind, StrikeResult.ContactKind.POKE, "classified as POKE")
	assert_true(strike.lethal, "dashing onto a point triggers the lethal threshold")


func test_poor_burst_alignment_downgrades_to_poke() -> void:
	## A burst with 45° facing offset misaligns the burst direction with the
	## blade axis → geometry-first classification yields POKE rather than THRUST
	## (COMBAT-010). Even if the intent was a thrust, the physics evaluates what
	## actually happened. A POKE at low speed is survivable.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, deg_to_rad(45.0))
	DuelFixture.place(b, _rules.weapon.tip_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.weapon.speed = 0.0
	a.weapon.swing_dir = 1.0
	a.vx = 3.0
	_make_thrust(a)
	var tip_x := a.x + _rules.weapon.tip_radius
	var strike := DamageModel.evaluate(a, b, tip_x, 0.0, _rules)
	assert_eq(strike.contact_kind, StrikeResult.ContactKind.POKE, "poor burst alignment → POKE, not THRUST")
	assert_false(strike.lethal, "a poke at low speed is not lethal")
	assert_true(strike.damage < _rules.fighter.max_health, "poor alignment → survivable")


func test_thrust_is_always_lethal() -> void:
	## COMBAT-011: a THRUST is an instant kill regardless of speed or severity.
	## Defense is handled by the chronological TOI solver: if a blade contact
	## redirects the weapon, the thrust classification changes or disappears.
	## A thrust that still physically qualifies after any deflection lands.
	var data := _pair(1.0)
	var a: FighterState = data[1]
	var b: FighterState = data[2]
	_make_thrust(a)
	var strike := _evaluate_tip(a, b)
	assert_true(strike.lethal, "a thrust is always lethal")
	assert_eq(strike.damage, _rules.fighter.max_health, "damage equals max health")


func test_thrust_lethal_at_any_speed() -> void:
	## COMBAT-011: a THRUST is lethal even at minimal forward velocity. The
	## lethality rule is classification-based, not severity-based.
	var data := _pair(0.5)
	var a: FighterState = data[1]
	var b: FighterState = data[2]
	_make_thrust(a)
	var strike := DamageModel.evaluate(a, b, a.x + _rules.weapon.tip_radius, 0.0, _rules)
	assert_true(strike.lethal, "even a slow thrust is lethal")
	assert_eq(strike.damage, _rules.fighter.max_health, "slow thrust still deals max health")


func test_poke_severity_curve_is_continuous() -> void:
	## COMBAT-011: one physical severity model for base evaluation. Two pokes
	## at different speeds produce proportionally different damage from the
	## same continuous severity curve. There is no classification-specific
	## multiplier — classification affects lethality thresholds, not the base
	## severity calculation.
	var data_slow := _pair(4.0)
	var a_slow: FighterState = data_slow[1]
	var b_slow: FighterState = data_slow[2]
	var slow_poke := _evaluate_tip(a_slow, b_slow)
	var data_fast := _pair(8.0)
	var a_fast: FighterState = data_fast[1]
	var b_fast: FighterState = data_fast[2]
	var fast_poke := _evaluate_tip(a_fast, b_fast)
	assert_eq(slow_poke.contact_kind, StrikeResult.ContactKind.POKE, "precondition: slow poke")
	assert_eq(fast_poke.contact_kind, StrikeResult.ContactKind.POKE, "precondition: fast poke")
	assert_true(fast_poke.damage > slow_poke.damage, "faster poke → more damage from the shared severity curve")


func test_one_severity_curve_not_two() -> void:
	var data := _pair(8.0)
	var a: FighterState = data[1]
	var b: FighterState = data[2]
	var poke := _evaluate_tip(a, b)
	assert_eq(poke.contact_kind, StrikeResult.ContactKind.POKE, "precondition")
	var fast_data := _pair(12.0)
	var fast_a: FighterState = fast_data[1]
	var fast_b: FighterState = fast_data[2]
	var fast_poke := _evaluate_tip(fast_a, fast_b)
	assert_true(fast_poke.damage > poke.damage, "faster poke does more damage — continuous severity curve")


func test_poke_damage_increases_with_target_closing() -> void:
	var data1 := _pair(6.0)
	var a1: FighterState = data1[1]
	var b1: FighterState = data1[2]
	var still := _evaluate_tip(a1, b1)
	var data2 := _pair(6.0)
	var a2: FighterState = data2[1]
	var b2: FighterState = data2[2]
	b2.vx = -4.0
	var closing := _evaluate_tip(a2, b2)
	assert_true(closing.damage > still.damage, "target motion participates in severity (PHYS-001)")
