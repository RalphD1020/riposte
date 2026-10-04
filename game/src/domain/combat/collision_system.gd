class_name CollisionSystem
extends RefCounted

## Swept, deterministic collision (COMBAT §42, PLAN Phase 5). Between the
## start and end poses of a tick the system walks substeps sized so no blade
## point travels more than `substep_travel`. Segment distance is 1-Lipschitz
## in point motion, so a contact band wider than one substep of travel cannot
## be tunneled. The earliest substep with any contact is reported. Blades that
## already touch at the start of the tick must separate before a new impact
## registers. Godot physics never decides a hit (SIM-001).
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


## Fill `report` with the earliest contacts between `start` and `finish`.
## `blades_enabled` is false during the blade contact cooldown.
func detect(
	state: MatchState,
	start: Array[FighterPose],
	finish: Array[FighterPose],
	rules: DuelRules,
	blades_enabled: bool,
	report: ContactReport
) -> void:
	report.clear()
	var weapon := rules.weapon
	var blade_touch := weapon.blade_radius * 2.0
	var body_touch := rules.fighter.body_radius + weapon.blade_radius
	var can_strike: Array[bool] = [_can_strike(state.fighter(0)), _can_strike(state.fighter(1))]
	if not blades_enabled and not can_strike[0] and not can_strike[1]:
		return
	_interpolate(start, finish, 0.0)
	var blades_touching := blades_enabled and _blade_distance(weapon) <= blade_touch
	var steps := substep_count(start, finish, rules)
	for k in range(1, steps + 1):
		var s := float(k) / float(steps)
		_interpolate(start, finish, s)
		if blades_enabled:
			var distance := _blade_distance(weapon)
			if blades_touching:
				blades_touching = distance <= blade_touch
			elif distance <= blade_touch:
				report.blade = true
				report.blade_ax = _contact.ax
				report.blade_ay = _contact.ay
				report.blade_bx = _contact.bx
				report.blade_by = _contact.by
		if not report.blade:
			for attacker in 2:
				if can_strike[attacker] and _body_hit(attacker, weapon, body_touch, report):
					report.body[attacker] = true
		if report.any():
			report.fraction = s
			return


static func _can_strike(fighter: FighterState) -> bool:
	return CombatPhase.is_striking(fighter.weapon.phase) and not fighter.weapon.swing_hit


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
