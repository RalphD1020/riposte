extends TestCase

## POINT-STRIKE: emergent contact classification (COMBAT-010, COMBAT-011) and
## shared contact kinematics (PHYS-007). Classification describes how a
## contact arose; one physical severity model for all kinds.
##
## Implements: /spec/invariants.md#combat-010, #combat-011, #phys-007
## See also: /docs/concepts/combat.md

var _rules: DuelRules


func _init() -> void:
	suite_name = "POINT"
	_rules = DuelFixture.rules()


## Helper: arm fighter 0 as if thrusting forward into fighter 1.
## Fighter B is placed so the blade tip just meets the body surface.
func _thrust_pair() -> MatchState:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, _rules.weapon.tip_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.swing_dir = 1.0
	a.weapon.angle = 0.0
	a.weapon.speed = 0.0
	a.vx = 6.0
	return state


## --- ImpactModel kinematics (PHYS-007) --------------------------------------


func test_axial_speed_from_body_translation() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	assert_true(impact.axial_speed > 0.0, "body translation contributes to axial speed")
	assert_near(impact.axial_speed, a.vx, 0.5, "tip speed dominated by body velocity when weapon is still")


func test_axial_speed_zero_for_perpendicular_swing() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	var reach := _rules.weapon.tip_radius + _rules.fighter.body_radius
	DuelFixture.place(b, reach, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.weapon.speed = 15.0
	a.weapon.swing_dir = 1.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	assert_true(impact.axial_speed < 1.0, "a perpendicular swing has negligible axial speed")
	assert_true(impact.thrust_alignment < 0.2, "low thrust alignment for a swing")


func test_incidence_quality_head_on() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	assert_between(impact.incidence_quality, 0.5, 1.0, "head-on entry has high incidence quality")


func test_incidence_quality_tangential() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, 0.0, _rules.weapon.tip_radius + _rules.fighter.body_radius, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.vx = 5.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	assert_true(impact.incidence_quality < 0.3, "tangential contact has low incidence quality")


## --- Classification (COMBAT-010) ---------------------------------------------


func test_normal_swing_is_slash() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	var mid_radius := _rules.weapon.hilt_radius + _rules.weapon.blade_length() * 0.5
	DuelFixture.place(b, mid_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.speed = 15.0
	a.weapon.swing_dir = 1.0
	a.weapon.angle = deg_to_rad(-20.0)
	a.vx = 3.0
	var contact_x := b.x - _rules.fighter.body_radius
	var impact := ImpactModel.resolve(a, b, contact_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_eq(kind, StrikeResult.ContactKind.SLASH, "a normal swing is SLASH")


func test_tip_contact_with_forward_motion_is_poke() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_eq(kind, StrikeResult.ContactKind.POKE, "tip contact with forward motion is POKE")


func test_poke_requires_tip_region() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	var mid_x := a.x + _rules.weapon.hilt_radius + _rules.weapon.blade_length() * 0.3
	var impact := ImpactModel.resolve(a, b, mid_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_ne(kind, StrikeResult.ContactKind.POKE, "mid-blade contact is not a POKE even with forward motion")


func test_poke_requires_sufficient_alignment() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	var reach := _rules.weapon.tip_radius + _rules.fighter.body_radius
	DuelFixture.place(b, reach, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.weapon.speed = 15.0
	a.weapon.swing_dir = 1.0
	a.vx = 0.5
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_ne(kind, StrikeResult.ContactKind.POKE, "tip contact without sufficient axial alignment is not a POKE")


func test_thrust_requires_burst() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	assert_false(a.gesture.is_bursting(), "precondition: not bursting")
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_eq(kind, StrikeResult.ContactKind.POKE, "without burst, it is a POKE not a THRUST")


func test_thrust_with_aligned_burst() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_eq(kind, StrikeResult.ContactKind.THRUST, "forward burst aligned with sword axis is THRUST")


func test_thrust_requires_burst_alignment_with_sword() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.LEFT_STEP
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 0.0
	a.gesture.burst_dir_y = -1.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_ne(kind, StrikeResult.ContactKind.THRUST, "lateral burst is not a THRUST")


func test_weapon_without_supports_thrust_cannot_poke() -> void:
	var no_thrust := DuelFixture.rules()
	no_thrust.weapon.supports_thrust = false
	var state := DuelFixture.state(no_thrust)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	var mid_radius := no_thrust.weapon.hilt_radius + no_thrust.weapon.blade_length() * 0.5
	DuelFixture.place(b, mid_radius + no_thrust.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.speed = 15.0
	a.weapon.swing_dir = 1.0
	a.weapon.angle = deg_to_rad(-20.0)
	a.vx = 3.0
	var contact_x := b.x - no_thrust.fighter.body_radius
	var impact := ImpactModel.resolve(a, b, contact_x, 0.0, no_thrust)
	var kind := DamageModel.classify_contact(impact, a, no_thrust)
	assert_eq(kind, StrikeResult.ContactKind.SLASH, "weapon without supports_thrust classifies as SLASH")


## --- Severity model (COMBAT-011) ---------------------------------------------


func test_one_severity_model_for_poke_and_thrust() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	var tip_x := a.x + _rules.weapon.tip_radius
	var poke_strike := DamageModel.evaluate(a, b, tip_x, 0.0, _rules)
	assert_eq(poke_strike.contact_kind, StrikeResult.ContactKind.POKE, "precondition: this is a POKE")
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0
	a.vx = 10.0
	var thrust_strike := DamageModel.evaluate(a, b, tip_x, 0.0, _rules)
	assert_eq(thrust_strike.contact_kind, StrikeResult.ContactKind.THRUST, "precondition: this is a THRUST")
	assert_true(thrust_strike.damage > poke_strike.damage, "THRUST naturally deals more damage than POKE from higher energy")


func test_point_strike_severity_uses_axial_velocity() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var b := state.fighter(1)
	var tip_x := a.x + _rules.weapon.tip_radius
	var slow_poke := DamageModel.evaluate(a, b, tip_x, 0.0, _rules)
	a.vx = 12.0
	var fast_poke := DamageModel.evaluate(a, b, tip_x, 0.0, _rules)
	assert_true(fast_poke.damage > slow_poke.damage, "higher axial speed means more damage")


func test_poke_severity_depends_on_incidence() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	var reach := _rules.weapon.tip_radius + _rules.fighter.body_radius
	DuelFixture.place(b, reach, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.angle = 0.0
	a.vx = 8.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var direct := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	DuelFixture.place(b, reach, 0.3, PI)
	var angled := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	assert_true(direct.incidence_quality > angled.incidence_quality, "head-on has better incidence than angled")


## --- Events ------------------------------------------------------------------


func test_body_poke_event_emitted() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var tip_x := a.x + _rules.weapon.tip_radius
	var report := ContactFixture.body_report(0, tip_x, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var pokes := DuelFixture.of_type(events, DuelEventTypes.BODY_POKE)
	var hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
	assert_true(hits.size() >= 1, "BODY_HIT always emitted")
	assert_eq(pokes.size(), 1, "BODY_POKE emitted alongside BODY_HIT for a poke")


func test_body_thrust_event_emitted() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0
	a.vx = 10.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var report := ContactFixture.body_report(0, tip_x, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var thrusts := DuelFixture.of_type(events, DuelEventTypes.BODY_THRUST)
	assert_eq(thrusts.size(), 1, "BODY_THRUST emitted for a thrust")


func test_slash_emits_no_point_strike_event() -> void:
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	var mid_radius := _rules.weapon.hilt_radius + _rules.weapon.blade_length() * 0.5
	DuelFixture.place(b, mid_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.ACTIVE_THREAT
	a.weapon.speed = 15.0
	a.weapon.swing_dir = 1.0
	a.weapon.angle = deg_to_rad(-20.0)
	var contact_x := b.x - _rules.fighter.body_radius
	var report := ContactFixture.body_report(0, contact_x, 0.1)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_POKE).size(), 0, "no BODY_POKE for a slash")
	assert_eq(DuelFixture.of_type(events, DuelEventTypes.BODY_THRUST).size(), 0, "no BODY_THRUST for a slash")


func test_event_payload_carries_thrust_alignment() -> void:
	var state := _thrust_pair()
	var a := state.fighter(0)
	var tip_x := a.x + _rules.weapon.tip_radius
	var report := ContactFixture.body_report(0, tip_x, 0.0)
	var events: Array[DuelEvent] = []
	ContactResolver.resolve(state, report, _rules, 0, 0.5, events)
	var hits := DuelFixture.of_type(events, DuelEventTypes.BODY_HIT)
	assert_eq(hits.size(), 1, "one hit event")
	assert_true(hits[0].data[DuelEventKeys.THRUST_ALIGNMENT] > 0.0, "thrust alignment carried in payload")
	assert_true(hits[0].data[DuelEventKeys.INCIDENCE_QUALITY] > 0.0, "incidence quality carried in payload")


## --- Neutral-phase stabs (COMBAT-010, PHYS-007) ------------------------------
## A point strike is a contact classification, never an input, attack state,
## animation, or special move. A stationary sword on an advancing fighter is a
## valid source.


func _neutral_stab_pair(body_speed: float) -> MatchState:
	## Fighter 0 walks forward with sword in NEUTRAL phase, tip pointing at
	## the opponent. Fighter 1 is placed so the blade tip just meets the body.
	var state := DuelFixture.state(_rules)
	var a := state.fighter(0)
	var b := state.fighter(1)
	DuelFixture.place(a, 0.0, 0.0, 0.0)
	DuelFixture.place(b, _rules.weapon.tip_radius + _rules.fighter.body_radius, 0.0, PI)
	a.weapon.phase = CombatPhase.Id.NEUTRAL
	a.weapon.angle = 0.0
	a.weapon.speed = 0.0
	a.vx = body_speed
	return state


func test_neutral_forward_stab_classifies_as_poke() -> void:
	var state := _neutral_stab_pair(6.0)
	var a := state.fighter(0)
	var b := state.fighter(1)
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_eq(kind, StrikeResult.ContactKind.POKE, "neutral blade advancing tip-first classifies as POKE")


func test_neutral_forward_dash_classifies_as_thrust() -> void:
	var state := _neutral_stab_pair(8.0)
	var a := state.fighter(0)
	var b := state.fighter(1)
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var impact := ImpactModel.resolve(a, b, tip_x, 0.0, _rules)
	var kind := DamageModel.classify_contact(impact, a, _rules)
	assert_eq(kind, StrikeResult.ContactKind.THRUST, "neutral dash with sword aligned is THRUST")


func test_neutral_stab_produces_damage() -> void:
	var state := _neutral_stab_pair(6.0)
	var a := state.fighter(0)
	var b := state.fighter(1)
	var tip_x := a.x + _rules.weapon.tip_radius
	var strike := DamageModel.evaluate(a, b, tip_x, 0.0, _rules)
	assert_true(strike.damage > 0.0, "neutral-phase stab deals damage")
	assert_eq(strike.contact_kind, StrikeResult.ContactKind.POKE, "classified as POKE")


func test_neutral_dash_thrust_is_instant_kill() -> void:
	## COMBAT-011: a THRUST is always lethal. The weapon phase is NEUTRAL but
	## the fighter is dashing forward with the sword aligned — same physics.
	var state := _neutral_stab_pair(10.0)
	var a := state.fighter(0)
	var b := state.fighter(1)
	a.gesture.mode = MovementGestureState.Mode.BURST
	a.gesture.burst_kind = MovementGestureState.BurstKind.FORWARD_DASH
	a.gesture.burst_ticks_remaining = 5
	a.gesture.burst_dir_x = 1.0
	a.gesture.burst_dir_y = 0.0
	var tip_x := a.x + _rules.weapon.tip_radius
	var strike := DamageModel.evaluate(a, b, tip_x, 0.0, _rules)
	assert_eq(strike.contact_kind, StrikeResult.ContactKind.THRUST, "classified as THRUST")
	assert_true(strike.lethal, "neutral-phase thrust is lethal")
	assert_eq(strike.damage, _rules.fighter.max_health, "deals max health damage")
