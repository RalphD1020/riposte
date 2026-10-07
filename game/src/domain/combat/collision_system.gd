class_name CollisionSystem
extends RefCounted

## Swept, deterministic collision (COMBAT §42–§45). Between the start and end
## poses of an interval the system walks substeps sized so no blade point
## travels more than `substep_travel`. Segment distance is 1-Lipschitz in
## point motion, so a contact band wider than one substep of travel cannot be
## tunneled. The earliest substep with any contact is reported.
##
## Whether a touch is a *new* contact is the `ContactPairState` lifecycle's
## decision, not a cooldown counter's: blades already touching must genuinely
## separate before they can strike again. Godot physics never decides a hit
## (SIM-001).
##
## Implements: /spec/invariants.md#combat-002
## See also: /docs/concepts/combat.md

const FRAME_STRIDE := 4

var _contact := SegmentContact.new()
## Interpolated frame per fighter: [x, y, blade ux, blade uy] × 2. Reused to
## keep the substep loop allocation-free.
var _frame := PackedFloat64Array([0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0, 0.0])


static func substep_count(start: Array[FighterPose], finish: Array[FighterPose], rules: DuelRules) -> int:
	var travel := 0.0
	for i in 2:
		travel += SimMath.length(finish[i].x - start[i].x, finish[i].y - start[i].y)
		travel += rules.weapon.tip_radius * absf(SimMath.wrap_angle(finish[i].blade_angle - start[i].blade_angle))
	return clampi(ceili(travel / rules.combat.substep_travel), 1, rules.combat.max_substeps)


## Fill `report` with the earliest contacts in the sub-interval between `start`
## and `finish`, advancing the blade pair's lifecycle as the sweep passes
## through it. Weapon-body lifecycles gate re-entry so a penetrating sword
## does not multi-hit (COMBAT-007, PHYS-008).
##
## `report.fraction` is relative to this sub-interval, so a chronological
## caller sweeping the remainder of a tick gets the earliest contact *in that
## remainder* rather than a stale whole-tick ordering.
func detect(
	state: MatchState,
	start: Array[FighterPose],
	finish: Array[FighterPose],
	rules: DuelRules,
	pair: ContactPairState,
	report: ContactReport
) -> void:
	report.clear()
	var weapon := rules.weapon
	var blade_touch := weapon.blade_radius * 2.0
	var epsilon := rules.combat.separation_epsilon
	var body_touch := rules.fighter.body_radius + weapon.blade_radius
	var can_strike: Array[bool] = [_can_contact_body(state.fighter(0)), _can_contact_body(state.fighter(1))]
	var body_touch_body := rules.fighter.body_radius * 2.0
	var steps := substep_count(start, finish, rules)
	for k in range(1, steps + 1):
		var s := float(k) / float(steps)
		_interpolate(start, finish, s)
		if not pair.is_bound() and pair.observe(_blade_distance(weapon), blade_touch, epsilon):
			report.blade = true
			report.blade_ax = _contact.ax
			report.blade_ay = _contact.ay
			report.blade_bx = _contact.bx
			report.blade_by = _contact.by
		if not report.blade:
			for attacker in 2:
				if can_strike[attacker] and _body_hit_with_lifecycle(attacker, weapon, body_touch, epsilon, state.weapon_body_contacts[attacker], report):
					report.body[attacker] = true
		if not report.blade and not report.body[0] and not report.body[1]:
			if _body_push(body_touch_body, report):
				report.body_push = true
		if report.any():
			report.fraction = s
			return


## Whether this fighter's blade participates in weapon→body contact detection
## (COMBAT-010, PHYS-007). A point strike is a contact classification, never
## an attack state: a stationary sword on an advancing fighter is a valid
## source. Only DEAD and FALLING exclude detection — the blade is inert.
##
## BIND contacts are detected geometrically and suppressed at the consequence
## layer (ContactResolver), not here. Combat state may change the consequence
## of contact but must not make real geometry cease to exist.
static func _can_contact_body(fighter: FighterState) -> bool:
	return fighter.weapon.phase != CombatPhase.Id.DEAD and not fighter.is_falling


## Normalized-lerp blade direction: per-tick rotation is small, and the result
## stays deterministic without trigonometry.
func _interpolate(start: Array[FighterPose], finish: Array[FighterPose], s: float) -> void:
	for i in 2:
		var from := start[i]
		var to := finish[i]
		var ux := SimMath.mix(from.ux, to.ux, s)
		var uy := SimMath.mix(from.uy, to.uy, s)
		var length := SimMath.length(ux, uy)
		if length > SimMath.EPSILON:
			ux /= length
			uy /= length
		else:
			ux = to.ux
			uy = to.uy
		var base := i * FRAME_STRIDE
		_frame[base] = SimMath.mix(from.x, to.x, s)
		_frame[base + 1] = SimMath.mix(from.y, to.y, s)
		_frame[base + 2] = ux
		_frame[base + 3] = uy


func _blade_distance(weapon: WeaponDefinition) -> float:
	var hilt := weapon.hilt_radius
	var tip := weapon.tip_radius
	SimMath.closest_segments(
		_frame[0] + _frame[2] * hilt, _frame[1] + _frame[3] * hilt,
		_frame[0] + _frame[2] * tip, _frame[1] + _frame[3] * tip,
		_frame[4] + _frame[6] * hilt, _frame[5] + _frame[7] * hilt,
		_frame[4] + _frame[6] * tip, _frame[5] + _frame[7] * tip,
		_contact
	)
	return _contact.distance


func _body_hit(attacker: int, weapon: WeaponDefinition, body_touch: float, report: ContactReport) -> bool:
	var a := attacker * FRAME_STRIDE
	var d := (1 - attacker) * FRAME_STRIDE
	var hx := _frame[a] + _frame[a + 2] * weapon.hilt_radius
	var hy := _frame[a + 1] + _frame[a + 3] * weapon.hilt_radius
	var tx := _frame[a] + _frame[a + 2] * weapon.tip_radius
	var ty := _frame[a + 1] + _frame[a + 3] * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, _frame[d], _frame[d + 1])
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	if SimMath.length(_frame[d] - px, _frame[d + 1] - py) > body_touch:
		return false
	report.body_x[attacker] = px
	report.body_y[attacker] = py
	return true


## Body hit gated by the weapon-body entry lifecycle (COMBAT-007).
## Returns true only on a new entry (OUTSIDE → ENTERED). A sword that is
## already inside the body volume does not re-damage.
func _body_hit_with_lifecycle(attacker: int, weapon: WeaponDefinition, body_touch: float, epsilon: float, lifecycle: WeaponBodyContact, report: ContactReport) -> bool:
	var gap := _body_gap(attacker, weapon)
	if not lifecycle.observe(gap, body_touch, epsilon):
		return false
	var a := attacker * FRAME_STRIDE
	var d := (1 - attacker) * FRAME_STRIDE
	var hx := _frame[a] + _frame[a + 2] * weapon.hilt_radius
	var hy := _frame[a + 1] + _frame[a + 3] * weapon.hilt_radius
	var tx := _frame[a] + _frame[a + 2] * weapon.tip_radius
	var ty := _frame[a + 1] + _frame[a + 3] * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, _frame[d], _frame[d + 1])
	report.body_x[attacker] = SimMath.mix(hx, tx, t)
	report.body_y[attacker] = SimMath.mix(hy, ty, t)
	return true


## Distance from attacker's blade to the defender's body center.
func _body_gap(attacker: int, weapon: WeaponDefinition) -> float:
	var a := attacker * FRAME_STRIDE
	var d := (1 - attacker) * FRAME_STRIDE
	var hx := _frame[a] + _frame[a + 2] * weapon.hilt_radius
	var hy := _frame[a + 1] + _frame[a + 3] * weapon.hilt_radius
	var tx := _frame[a] + _frame[a + 2] * weapon.tip_radius
	var ty := _frame[a + 1] + _frame[a + 3] * weapon.tip_radius
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, _frame[d], _frame[d + 1])
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	return SimMath.length(_frame[d] - px, _frame[d + 1] - py)


## Two fighter bodies overlap at the current interpolated position. Returns
## true when the gap is within the combined body radius, filling the report
## normal from fighter 0 toward fighter 1.
func _body_push(touch: float, report: ContactReport) -> bool:
	var dx := _frame[FRAME_STRIDE] - _frame[0]
	var dy := _frame[FRAME_STRIDE + 1] - _frame[1]
	var dist := SimMath.length(dx, dy)
	if dist >= touch:
		return false
	if dist > SimMath.EPSILON:
		report.body_push_nx = dx / dist
		report.body_push_ny = dy / dist
	else:
		report.body_push_nx = 1.0
		report.body_push_ny = 0.0
	return true
