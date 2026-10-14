class_name CollisionSystem
extends RefCounted

## Swept, deterministic collision (COMBAT §42–§45). Between the start and end
## poses of an interval the system walks substeps sized so no blade point
## travels more than `substep_travel`. Segment distance is 1-Lipschitz in
## point motion, so a contact band wider than one substep of travel cannot be
## tunneled. The earliest substep with any contact is reported.
##
## Whether a touch is a *new* contact is the `SwordContactSet` lifecycle's
## decision, not a cooldown counter's: blades already touching must genuinely
## separate before they can strike again. The manifold also records where the
## blades touch on every substep they do, new contact or not. Godot physics
## never decides a hit (SIM-001).
##
## Implements: /spec/invariants.md#combat-002
## See also: /docs/concepts/combat.md

const FRAME_STRIDE := 6
## Frame slots: body centre, sword origin (from `WeaponKinematics`), blade
## direction.
const CENTER_X := 0
const CENTER_Y := 1
const PIVOT_X := 2
const PIVOT_Y := 3
const BLADE_UX := 4
const BLADE_UY := 5
## Cap counters; the owning simulation shares its own instance.
var diagnostics := ContactDiagnostics.new()
var _geometry := SwordContactGeometry.new()
## Interpolated frame per fighter (see the slots above) × 2. Reused to keep the
## substep loop allocation-free.
var _frame := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
var _blade := BladePose.new()
## Each attacker's blade-to-body gap at the previous substep.
var _previous_body := PackedFloat64Array([0.0, 0.0])
## Each attacker's blade's surface gap to the opponent's nearer hand disc at the
## previous substep, and which grip that nearer hand is on (HAND-CONTACT-001).
var _previous_hand := PackedFloat64Array([0.0, 0.0])
## The hand gap a sweep records for a hand it has proven clear (any positive
## value: only the sign and the crossing are read).
const HANDS_CLEAR := 1.0
## Below this much clearance (m) the bound defers to the exact gap, so rounding
## at the boundary can never read a sign the exact measurement would not.
const CLEAR_MARGIN := 1.0e-9
var _hand_grip := PackedFloat64Array([0.0, 0.0])
## Each attacker's re-hold line for this sweep (centre distance).
var _body_hold := PackedFloat64Array([0.0, 0.0])
## Each attacker's blade-to-body touch distance: the target's hurt torso plus
## the attacker's own blade.
var _body_touch := PackedFloat64Array([0.0, 0.0])


## Substeps so no blade point travels more than `substep_travel`: body travel,
## the tip's arc, and the carriage's own travel along the attack track
## (WEAPON-PATH-003), which the curved track adds on top. Fixed caps, fixed
## order — never "until converged".
static func substep_count(start: Array[FighterPose], finish: Array[FighterPose], rules: DuelRules) -> int:
	return clampi(substeps_wanted(start, finish, rules), 1, rules.combat.max_substeps)


## Substeps the motion would need with no cap. Above `max_substeps` the sweep
## is capped (bounded work) and the overflow is counted.
static func substeps_wanted(start: Array[FighterPose], finish: Array[FighterPose], rules: DuelRules) -> int:
	var travel := 0.0
	for i in 2:
		var spec := rules.combatant(i)
		travel += SimMath.length(finish[i].x - start[i].x, finish[i].y - start[i].y)
		travel += spec.weapon.tip_radius * absf(SimMath.wrap_angle(finish[i].blade_angle - start[i].blade_angle))
		if not spec.handling.attack_path.is_fixed():
			travel += SimMath.length(
				(finish[i].carriage_x - finish[i].x) - (start[i].carriage_x - start[i].x),
				(finish[i].carriage_y - finish[i].y) - (start[i].carriage_y - start[i].y)
			)
	return ceili(travel / rules.combat.substep_travel)


## Fill `report` with the earliest contacts in the sub-interval between `start`
## and `finish`, advancing the blade pair's lifecycle as the sweep passes
## through it. Weapon-body lifecycles gate re-entry so a penetrating sword
## does not multi-hit (COMBAT-007, PHYS-008). The body-body lifecycle
## (PHYS-009) distinguishes new impacts from persistent contacts.
##
## `report.fraction` is relative to this sub-interval, so a chronological
## caller sweeping the remainder of a tick gets the earliest contact *in that
## remainder* rather than a stale whole-tick ordering. `holds` allows held
## (persistent) contacts to be reported, `bodies` the body-body contact.
func detect(
	state: MatchState,
	start: Array[FighterPose],
	finish: Array[FighterPose],
	rules: DuelRules,
	manifold: SwordContactSet,
	report: ContactReport,
	holds: bool = true,
	bodies: bool = true
) -> void:
	report.clear()
	## Sword↔sword is measured as a surface gap over the swords' features
	## (blade and guard, `SwordContactGeometry`): touching is a gap of zero.
	var blade_touch := 0.0
	var epsilon := rules.combat.separation_epsilon
	for attacker in 2:
		_body_touch[attacker] = rules.combatant(1 - attacker).fighter.hurt_radius + rules.combatant(attacker).weapon.blade_radius
	var can_strike: Array[bool] = [_can_contact_body(state.fighter(0)), _can_contact_body(state.fighter(1))]
	## A hand can be wounded once per attack by a feature that wounds, while its
	## owner can still be struck (HAND-CONTACT-001).
	var hands_open: Array[bool] = [_hands_open(state, 0, rules, can_strike[0]), _hands_open(state, 1, rules, can_strike[1])]
	var body_touch_body := rules.combatant(0).fighter.push_radius + rules.combatant(1).fighter.push_radius
	var wanted := substeps_wanted(start, finish, rules)
	if wanted > rules.combat.max_substeps:
		diagnostics.ccd_cap_hits += 1
	var steps := clampi(wanted, 1, rules.combat.max_substeps)
	## Gaps at the start of the interval: a persisted pair is reported on the
	## substep its overlap passes twice the contact slop — coming back into
	## touch, or a held contact being driven deeper (RIGID-CONTACT-001). Held
	## contacts rest at the slop itself, so the line is well clear of where they
	## rest and rounding never decides whether one is re-held. A pair already
	## past it was held before this motion was carried; reporting it again
	## every substep would only spend the contact budget.
	##
	## The line is also never closer than one more slop below where this sweep
	## starts. A pair re-held mid-tick rests at the line itself, so without
	## that a fast-turning contact's second-order drift would re-hold it on
	## every substep; "driven deeper" means deeper than it was held.
	var slop := rules.combat.contact_slop
	_interpolate(start, finish, 0.0, rules)
	var previous_blade := _blade_distance(rules)
	_previous_body[0] = _body_gap(0, rules.combatant(0).weapon)
	_previous_body[1] = _body_gap(1, rules.combatant(1).weapon)
	_previous_hand[0] = _open_hand_gap(0, rules) if hands_open[0] else HANDS_CLEAR
	_previous_hand[1] = _open_hand_gap(1, rules) if hands_open[1] else HANDS_CLEAR
	var blade_hold := minf(blade_touch - 2.0 * slop, previous_blade - slop)
	_body_hold[0] = minf(_body_touch[0] - 2.0 * slop, _previous_body[0] - slop)
	_body_hold[1] = minf(_body_touch[1] - 2.0 * slop, _previous_body[1] - slop)
	for k in range(1, steps + 1):
		var s := float(k) / float(steps)
		_interpolate(start, finish, s, rules)
		var blade_gap := _blade_distance(rules)
		if blade_gap <= blade_touch:
			_record_blade_points(manifold, blade_touch)
		var blade_retouch := blade_gap <= blade_hold and previous_blade > blade_hold
		var blade_before := previous_blade
		previous_blade = blade_gap
		var rehold := NO_REHOLD
		if manifold.observe(blade_gap, blade_touch, epsilon):
			report.blade = true
			report.blade_ax = _geometry.ax
			report.blade_ay = _geometry.ay
			report.blade_bx = _geometry.bx
			report.blade_by = _geometry.by
		elif holds and blade_retouch and manifold.phase != SwordContactSet.Phase.SEPARATED:
			report.persistent = true
			rehold = REHOLD_BLADE
			_rehold_travel = blade_before - blade_gap
			_rehold_line = blade_hold
		## A hand is entered, never held: the gap crossing into it is the contact,
		## a blade already inside is not a new one. The hand reaches only a few
		## centimetres past the handle — less than a substep — so its entry is
		## refined within the substep by a fixed bisection, and so is the steel's
		## when a new sword contact began in the same substep: steel met first
		## shields the hand behind it; a hand reached first is struck.
		for attacker in 2:
			if not hands_open[attacker]:
				continue
			var hand_gap := _open_hand_gap(attacker, rules)
			var hand_before := _previous_hand[attacker]
			_previous_hand[attacker] = hand_gap
			if hand_gap <= 0.0 and hand_before > 0.0 and hands_open[attacker] and not report.hand[attacker]:
				var grip := _hand_grip[attacker]
				var previous_s := float(k - 1) / float(steps)
				var entered := _hand_entry(start, finish, attacker, previous_s, s, rules)
				var first := not report.blade or (blade_before > blade_touch and entered <= _steel_entry(start, finish, previous_s, s, blade_touch, rules))
				_interpolate(start, finish, s, rules)
				_blade_distance(rules)
				if first:
					report.hand[attacker] = true
					report.hand_grip[attacker] = grip
					report.hand_fraction[attacker] = entered
		if not report.blade:
			for attacker in 2:
				var lifecycle := state.weapon_body_contacts[attacker]
				var weapon := rules.combatant(attacker).weapon
				var gap := _body_gap(attacker, weapon)
				var body_retouch := gap <= _body_hold[attacker] and _previous_body[attacker] > _body_hold[attacker]
				var body_before := _previous_body[attacker]
				_previous_body[attacker] = gap
				if can_strike[attacker] and _body_hit_with_lifecycle(attacker, weapon, gap, _body_touch[attacker], epsilon, lifecycle, report):
					report.body[attacker] = true
				elif holds and body_retouch and can_strike[attacker] and lifecycle.phase == WeaponBodyContact.Phase.CONSTRAINING:
					report.persistent = true
					if rehold == NO_REHOLD:
						rehold = attacker
						_rehold_travel = body_before - gap
						_rehold_line = _body_hold[attacker]
		var apart := _body_distance()
		if bodies and not report.blade and not report.body[0] and not report.body[1] and apart < body_touch_body:
			_body_push_normal(apart, report)
			report.body_push = true
			report.body_push_persistent = state.body_contact.is_persistent_contact()
		## A hand is non-blocking: the sweep carries on past it, to whatever steel
		## or body lies behind (HAND-CONTACT-001).
		if report.blade or report.body[0] or report.body[1] or report.body_push or report.persistent:
			report.fraction = s
			## A held pair alone (nothing new, no hand) is re-held where it crossed
			## its line, not where the substep happened to end — otherwise a pair
			## driven slowly through a coarse substep sinks up to a substep of
			## travel past the line between re-holds (RIGID-CONTACT-001).
			var only_held := not (report.blade or report.body[0] or report.body[1] or report.body_push or report.hand[0] or report.hand[1])
			if only_held and rehold != NO_REHOLD:
				report.fraction = _rehold_crossing(start, finish, float(k - 1) / float(steps), s, rehold, slop, rules)
				if rehold == REHOLD_BLADE and _blade_distance(rules) <= blade_touch:
					_record_blade_points(manifold, blade_touch)
			return


## Whether this fighter's blade participates in weapon→body contact detection
## (COMBAT-010, PHYS-007). A point strike is a contact classification, never
## an attack state: a stationary sword on an advancing fighter is a valid
## source. Only DEAD and FALLING exclude detection — the blade is inert.
## Combat state may change the consequence of contact but must not make real
## geometry cease to exist.
static func _can_contact_body(fighter: FighterState) -> bool:
	return fighter.weapon.phase != CombatPhase.Id.DEAD and not fighter.is_falling


## Normalized-lerp blade direction: per-tick rotation is small, and the result
## stays deterministic without trigonometry. The origin follows the body on a
## fixed path; on a moving path it is resampled at the interpolated weapon
## angle and heading, so a curved manifold is swept along its curve, not its
## chord (WEAPON-PATH-001).
func _interpolate(start: Array[FighterPose], finish: Array[FighterPose], s: float, rules: DuelRules) -> void:
	for i in 2:
		var spec := rules.combatant(i)
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
		var cx := SimMath.mix(from.x, to.x, s)
		var cy := SimMath.mix(from.y, to.y, s)
		_frame[base + CENTER_X] = cx
		_frame[base + CENTER_Y] = cy
		if spec.handling.attack_path.is_fixed():
			_frame[base + PIVOT_X] = cx
			_frame[base + PIVOT_Y] = cy
		else:
			var facing := from.facing + SimMath.wrap_angle(to.facing - from.facing) * s
			WeaponKinematics.pose_at(cx, cy, facing, SimMath.mix(from.weapon_angle, to.weapon_angle, s), spec, _blade)
			_frame[base + PIVOT_X] = _blade.origin_x
			_frame[base + PIVOT_Y] = _blade.origin_y
		_frame[base + BLADE_UX] = ux
		_frame[base + BLADE_UY] = uy


## A point `r` down fighter `slot`'s interpolated blade.
func _blade_x(slot: int, r: float) -> float:
	var base := slot * FRAME_STRIDE
	return _frame[base + PIVOT_X] + _frame[base + BLADE_UX] * r


func _blade_y(slot: int, r: float) -> float:
	var base := slot * FRAME_STRIDE
	return _frame[base + PIVOT_Y] + _frame[base + BLADE_UY] * r


## Surface gap between the two interpolated swords' nearest features.
func _blade_distance(rules: DuelRules) -> float:
	return _geometry.measure(
		_frame[CENTER_X], _frame[CENTER_Y],
		_frame[PIVOT_X], _frame[PIVOT_Y], _frame[BLADE_UX], _frame[BLADE_UY],
		_frame[FRAME_STRIDE + PIVOT_X], _frame[FRAME_STRIDE + PIVOT_Y], _frame[FRAME_STRIDE + BLADE_UX], _frame[FRAME_STRIDE + BLADE_UY],
		rules.combatant(0).weapon, rules.combatant(1).weapon
	)


## Every touching point of the swords (from the last `_blade_distance`) as this
## tick's manifold, in the geometry's canonical order: where it lies, the
## features, each blade fraction (guard → point; a guard or hilt contact reads
## 0), its place on each feature and its own normal. A later substep of the
## same tick replaces the record.
func _record_blade_points(manifold: SwordContactSet, touch: float) -> void:
	manifold.begin_substep()
	var index := 0
	for point in _geometry.count:
		if _geometry.point_gap[point] > touch:
			continue
		manifold.record_point(
			index,
			_geometry.point_feature_a[point] as SwordContactSet.Feature,
			_geometry.point_feature_b[point] as SwordContactSet.Feature,
			(_geometry.point_ax[point] + _geometry.point_bx[point]) * 0.5,
			(_geometry.point_ay[point] + _geometry.point_by[point]) * 0.5,
			_geometry.point_fraction_a[point],
			_geometry.point_fraction_b[point],
			_geometry.point_nx[point],
			_geometry.point_ny[point],
			_geometry.point_local_a[point],
			_geometry.point_local_b[point]
		)
		index += 1
	diagnostics.observe_manifold(manifold)
	diagnostics.meaningful_contacts_dropped += _geometry.dropped_within(touch)


## Body hit gated by the weapon-body entry lifecycle (COMBAT-007).
## Returns true only on a new entry (OUTSIDE → ENTERED). A sword that is
## already inside the body volume does not re-damage.
func _body_hit_with_lifecycle(attacker: int, weapon: WeaponDefinition, gap: float, body_touch: float, epsilon: float, lifecycle: WeaponBodyContact, report: ContactReport) -> bool:
	if not lifecycle.observe(gap, body_touch, epsilon):
		return false
	var d := (1 - attacker) * FRAME_STRIDE
	var hx := _blade_x(attacker, weapon.hilt_radius)
	var hy := _blade_y(attacker, weapon.hilt_radius)
	var tx := _blade_x(attacker, weapon.tip_radius)
	var ty := _blade_y(attacker, weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, _frame[d + CENTER_X], _frame[d + CENTER_Y])
	report.body_x[attacker] = SimMath.mix(hx, tx, t)
	report.body_y[attacker] = SimMath.mix(hy, ty, t)
	return true


## Bisection steps that order a hand entry against steel inside one substep: a
## fixed count, never "until converged" (1/16 of a substep).
const ENTRY_REFINEMENT := 4

## Which held pair crossed its re-hold line this substep: a weapon→body pair is
## its attacker's slot, the swords are `REHOLD_BLADE`.
const NO_REHOLD := -1
const REHOLD_BLADE := 2
## The most bisection steps a re-hold is refined by (1/64 of a substep). The
## count is derived from how far the pair closed inside the substep — enough
## halvings to bring that within one slop — so a slow pair costs none.
const REHOLD_REFINEMENT_MAX := 6

## How far the re-held pair closed inside its substep, and its re-hold line.
var _rehold_travel := 0.0
var _rehold_line := 0.0


## Sweep fraction (within `from`–`to`) at which the held pair `rehold` came to
## its re-hold line, leaving the frame interpolated there.
func _rehold_crossing(start: Array[FighterPose], finish: Array[FighterPose], from: float, to: float, rehold: int, slop: float, rules: DuelRules) -> float:
	var halvings := 0
	var travel := _rehold_travel
	while travel > slop and halvings < REHOLD_REFINEMENT_MAX:
		travel *= 0.5
		halvings += 1
	var outside := from
	var inside := to
	for _i in halvings:
		var middle := (outside + inside) * 0.5
		_interpolate(start, finish, middle, rules)
		var gap := _blade_distance(rules) if rehold == REHOLD_BLADE else _body_gap(rehold, rules.combatant(rehold).weapon)
		if gap <= _rehold_line:
			inside = middle
		else:
			outside = middle
	_interpolate(start, finish, inside, rules)
	return inside


## Sweep fraction (within `from`–`to`, where the blade went from outside to
## inside a hand) at which `attacker`'s blade entered the opponent's hand.
func _hand_entry(start: Array[FighterPose], finish: Array[FighterPose], attacker: int, from: float, to: float, rules: DuelRules) -> float:
	var outside := from
	var inside := to
	for _i in ENTRY_REFINEMENT:
		var middle := (outside + inside) * 0.5
		_interpolate(start, finish, middle, rules)
		if _hand_gap(attacker, rules) <= 0.0:
			inside = middle
		else:
			outside = middle
	return inside


## Sweep fraction (within `from`–`to`) at which the swords came into touch.
func _steel_entry(start: Array[FighterPose], finish: Array[FighterPose], from: float, to: float, touch: float, rules: DuelRules) -> float:
	var apart := from
	var touching := to
	for _i in ENTRY_REFINEMENT:
		var middle := (apart + touching) * 0.5
		_interpolate(start, finish, middle, rules)
		if _blade_distance(rules) <= touch:
			touching = middle
		else:
			apart = middle
	return touching


## Whether `attacker` may wound a hand this sweep: it can strike, its blade
## wounds, its attack has not already struck a hand, and the opponent is a
## living fighter on the platform — the torso's rule.
static func _hands_open(state: MatchState, attacker: int, rules: DuelRules, can_strike: bool) -> bool:
	var target := state.opponent_of(attacker)
	return (
		can_strike
		and rules.combatant(attacker).weapon.wounds(SwordContactSet.Feature.BLADE)
		and not state.fighter(attacker).weapon.hand_struck
		and target.is_alive()
		and not target.is_falling
	)


## The opponent's nearer hand gap as the sweep reads it — only its sign and
## its crossing matter, so a hand certainly clear of `attacker`'s blade reads
## `HANDS_CLEAR` without measuring either disc: both grip markers lie within
## half their spacing of the grips' midpoint, so a blade farther than that
## (plus the disc and the blade's radius) from the midpoint is clear of both.
## Otherwise the exact gap (`_hand_gap`).
func _open_hand_gap(attacker: int, rules: DuelRules) -> float:
	var defending := rules.combatant(1 - attacker)
	var off := defending.weapon.offhand_grip_radius
	var dominant := defending.weapon.dominant_grip_radius
	var reach := absf(dominant - off) * 0.5 + defending.fighter.hand_radius + rules.combatant(attacker).weapon.blade_radius
	if _blade_to_grip(attacker, (off + dominant) * 0.5, rules) > reach + CLEAR_MARGIN:
		return HANDS_CLEAR
	return _hand_gap(attacker, rules)


## Surface gap from `attacker`'s blade to the opponent's nearer hand disc (the
## wielder's `hand_radius` about each grip marker on its own sword), recording
## which grip that hand is on.
func _hand_gap(attacker: int, rules: DuelRules) -> float:
	var defending := rules.combatant(1 - attacker)
	var off := _grip_gap(attacker, rules, defending.weapon.offhand_grip_radius)
	var dominant := _grip_gap(attacker, rules, defending.weapon.dominant_grip_radius)
	_hand_grip[attacker] = defending.weapon.offhand_grip_radius if off <= dominant else defending.weapon.dominant_grip_radius
	return minf(off, dominant)


## Surface gap from `attacker`'s blade to the opponent's hand at grip radius
## `grip`.
func _grip_gap(attacker: int, rules: DuelRules, grip: float) -> float:
	return _blade_to_grip(attacker, grip, rules) - rules.combatant(1 - attacker).fighter.hand_radius - rules.combatant(attacker).weapon.blade_radius


## Distance from `attacker`'s blade segment to the point `grip` down the
## opponent's sword.
func _blade_to_grip(attacker: int, grip: float, rules: DuelRules) -> float:
	var weapon := rules.combatant(attacker).weapon
	var d := 1 - attacker
	var gx := _blade_x(d, grip)
	var gy := _blade_y(d, grip)
	var hx := _blade_x(attacker, weapon.hilt_radius)
	var hy := _blade_y(attacker, weapon.hilt_radius)
	var tx := _blade_x(attacker, weapon.tip_radius)
	var ty := _blade_y(attacker, weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, gx, gy)
	return SimMath.length(gx - SimMath.mix(hx, tx, t), gy - SimMath.mix(hy, ty, t))

## Distance from attacker's blade to the defender's body center.
func _body_gap(attacker: int, weapon: WeaponDefinition) -> float:
	var d := (1 - attacker) * FRAME_STRIDE
	var hx := _blade_x(attacker, weapon.hilt_radius)
	var hy := _blade_y(attacker, weapon.hilt_radius)
	var tx := _blade_x(attacker, weapon.tip_radius)
	var ty := _blade_y(attacker, weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, _frame[d + CENTER_X], _frame[d + CENTER_Y])
	var px := SimMath.mix(hx, tx, t)
	var py := SimMath.mix(hy, ty, t)
	return SimMath.length(_frame[d + CENTER_X] - px, _frame[d + CENTER_Y] - py)


## Centre distance between the two fighter bodies at the current
## interpolated position.
func _body_distance() -> float:
	return SimMath.length(_frame[FRAME_STRIDE + CENTER_X] - _frame[CENTER_X], _frame[FRAME_STRIDE + CENTER_Y] - _frame[CENTER_Y])


## The body-body contact normal from fighter 0 toward fighter 1 at the current
## interpolated position, `distance` apart.
func _body_push_normal(distance: float, report: ContactReport) -> void:
	if distance > SimMath.EPSILON:
		report.body_push_nx = (_frame[FRAME_STRIDE + CENTER_X] - _frame[CENTER_X]) / distance
		report.body_push_ny = (_frame[FRAME_STRIDE + CENTER_Y] - _frame[CENTER_Y]) / distance
	else:
		report.body_push_nx = 1.0
		report.body_push_ny = 0.0
