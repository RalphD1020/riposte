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
## The manifold of the sweep in progress, whose guard sides each measure reads.
var _manifold: SwordContactSet = null
const FREE_GUARDS: PackedInt32Array = [0, 0]
## Interpolated frame per fighter (see the slots above) × 2. Reused to keep the
## substep loop allocation-free.
var _frame := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0])
var _blade := BladePose.new()
## Each attacker's blade-to-body gap at the previous substep.
var _previous_body := PackedFloat64Array([0.0, 0.0])
## Each attacker's blade's surface gap to the opponent's grip region at the
## previous substep (GRIP-NONBLOCKING-001).
var _previous_grip := PackedFloat64Array([0.0, 0.0])
## The grip gap a sweep records for a grip it has proven clear (any positive
## value: only the sign and the crossing are read).
const GRIP_CLEAR := 1.0
## Below this much clearance (m) the bound defers to the exact gap, so rounding
## at the boundary can never read a sign the exact measurement would not.
const CLEAR_MARGIN := 1.0e-9
## Two grip parts whose gaps differ by less than this (m) are equally near
## (`_grip_gap`): far below anything physical, far above rounding.
const PART_TIE := 1.0e-9
## The nearest grip part of the last exact `_grip_gap` per attacker: which part
## (`DuelEventKeys.SOURCE_*`) and where on the opponent's sword (along the
## blade from the pommel, across it).
var _grip_source: Array[String] = ["", ""]
var _grip_along := PackedFloat64Array([0.0, 0.0])
var _grip_across := PackedFloat64Array([0.0, 0.0])
## A grip entry found inside a substep after a new steel contact began in it
## (per attacker). The clash is solved first and the rest of the tick swept
## from it; the entry is then judged against the trajectory the clash left —
## chronology, never a shield. Cleared when the grip is reported or the blade
## is out of it, and every tick (`begin_tick`).
var _grip_pending := PackedByteArray([0, 0])
var _segment := SegmentContact.new()
## Each attacker's re-hold line for this sweep (centre distance).
var _body_hold := PackedFloat64Array([0.0, 0.0])
## Each attacker's blade-to-body touch distance: the target's hurt torso plus
## the attacker's own blade.
var _body_touch := PackedFloat64Array([0.0, 0.0])


## A new tick's chronological sweep begins: nothing is pending from the last.
func begin_tick() -> void:
	_grip_pending[0] = 0
	_grip_pending[1] = 0


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
	## Sword↔sword is measured as a surface gap between the swords' steel
	## (`SwordContactGeometry`, STEEL-TOPOLOGY-001): touching is a gap of zero.
	var blade_touch := 0.0
	var epsilon := rules.combat.separation_epsilon
	_manifold = manifold
	for attacker in 2:
		_body_touch[attacker] = rules.combatant(1 - attacker).fighter.hurt_radius + rules.combatant(attacker).weapon.blade_radius
	var can_strike: Array[bool] = [_can_contact_body(state.fighter(0)), _can_contact_body(state.fighter(1))]
	## A grip can be wounded once per attack, while its owner can still be
	## struck (GRIP-NONBLOCKING-001).
	var grips_open: Array[bool] = [_grip_open(state, 0, can_strike[0]), _grip_open(state, 1, can_strike[1])]
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
	_latch_guards(manifold, blade_touch, epsilon)
	_previous_body[0] = _body_gap(0, rules.combatant(0).weapon)
	_previous_body[1] = _body_gap(1, rules.combatant(1).weapon)
	for attacker in 2:
		_previous_grip[attacker] = _open_grip_gap(attacker, rules) if grips_open[attacker] else GRIP_CLEAR
		## An entry the last clash left pending is judged on this remainder: the
		## blade still inside the grip enters it now, against the motion the
		## clash left (and only real closing wounds). Out of it, nothing is left
		## to judge.
		if _grip_pending[attacker] == 1:
			if _previous_grip[attacker] <= 0.0 and grips_open[attacker]:
				_previous_grip[attacker] = GRIP_CLEAR
			else:
				_grip_pending[attacker] = 0
	var blade_hold := minf(blade_touch - 2.0 * slop, previous_blade - slop)
	_body_hold[0] = minf(_body_touch[0] - 2.0 * slop, _previous_body[0] - slop)
	_body_hold[1] = minf(_body_touch[1] - 2.0 * slop, _previous_body[1] - slop)
	for k in range(1, steps + 1):
		var s := float(k) / float(steps)
		_interpolate(start, finish, s, rules)
		var blade_gap := _blade_distance(rules)
		if _latch_guards(manifold, blade_touch, epsilon):
			## A guard pair just touched from its protected side: measure again
			## with its side decided, so this substep's steel includes it.
			blade_gap = _blade_distance(rules)
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
		## A grip is entered, never held: the gap crossing into it is the
		## contact, a blade already inside is not a new one. The grip is only a
		## few centimetres thick — less than a substep — so its entry is refined
		## within the substep by a fixed bisection, and so is the steel's when a
		## new sword contact began in the same substep. Whatever came first
		## happened first: a grip reached before the steel is struck now; one
		## reached after it is left pending, because the clash is solved first
		## and only the trajectory it leaves can say whether the blade goes on
		## into the grip (GRIP-NONBLOCKING-001).
		for attacker in 2:
			if not grips_open[attacker]:
				continue
			var grip_gap := _open_grip_gap(attacker, rules)
			var grip_before := _previous_grip[attacker]
			_previous_grip[attacker] = grip_gap
			if grip_gap <= 0.0 and grip_before > 0.0 and not report.grip[attacker]:
				var previous_s := float(k - 1) / float(steps)
				var entered := _grip_entry(start, finish, attacker, previous_s, s, rules)
				var steel_first := report.blade and (blade_before <= blade_touch or entered > _steel_entry(start, finish, previous_s, s, blade_touch, rules))
				## The struck point is where the blade is entering, at the entry.
				_interpolate(start, finish, entered, rules)
				_grip_gap(attacker, rules)
				if steel_first:
					_grip_pending[attacker] = 1
				else:
					_grip_pending[attacker] = 0
					report.grip[attacker] = true
					report.grip_along[attacker] = _grip_along[attacker]
					report.grip_across[attacker] = _grip_across[attacker]
					report.grip_source[attacker] = _grip_source[attacker]
					report.grip_fraction[attacker] = entered
				_interpolate(start, finish, s, rules)
				_blade_distance(rules)
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
		## or body lies behind (GRIP-NONBLOCKING-001).
		if report.blade or report.body[0] or report.body[1] or report.body_push or report.persistent:
			report.fraction = s
			## A held pair alone (nothing new, no hand) is re-held where it crossed
			## its line, not where the substep happened to end — otherwise a pair
			## driven slowly through a coarse substep sinks up to a substep of
			## travel past the line between re-holds (RIGID-CONTACT-001).
			var only_held := not (report.blade or report.body[0] or report.body[1] or report.body_push or report.grip[0] or report.grip[1])
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


## Surface gap between the two interpolated swords' steel, each guard pair at
## the side its contact decided.
func _blade_distance(rules: DuelRules) -> float:
	return _geometry.measure(
		_frame[CENTER_X], _frame[CENTER_Y],
		_frame[PIVOT_X], _frame[PIVOT_Y], _frame[BLADE_UX], _frame[BLADE_UY],
		_frame[FRAME_STRIDE + PIVOT_X], _frame[FRAME_STRIDE + PIVOT_Y], _frame[FRAME_STRIDE + BLADE_UX], _frame[FRAME_STRIDE + BLADE_UY],
		rules.combatant(0).weapon, rules.combatant(1).weapon,
		_manifold.guard_mode if _manifold != null else FREE_GUARDS
	)


## Decide each guard pair's side from the last `_blade_distance`
## (GUARD-PROTECTION-001): a free pair that comes into touch takes the side the
## blade arrived from — protected (steel from now on) or passing (the guard lets
## it on) — and keeps it until the pair has parted past the separation
## epsilon; a protected pair whose blade has gone clearly to the grip side
## (slipped off the quillon) passes from then on, and a passing one is never
## made protected while it touches. Returns true when a pair's steel changed,
## so the caller measures again.
func _latch_guards(manifold: SwordContactSet, touch: float, epsilon: float) -> bool:
	var changed := false
	for g in 2:
		var pair_gap := _geometry.guard_gap[g]
		var side := _geometry.guard_side_reading[g]
		var mode := manifold.guard_mode[g]
		if mode == SwordContactGeometry.GUARD_FREE and pair_gap <= touch:
			manifold.guard_mode[g] = SwordContactGeometry.GUARD_PROTECTED if side == 1 else SwordContactGeometry.GUARD_PASSING
			changed = changed or side == 1
		elif mode != SwordContactGeometry.GUARD_FREE and pair_gap > touch + epsilon:
			manifold.guard_mode[g] = SwordContactGeometry.GUARD_FREE
		elif mode == SwordContactGeometry.GUARD_PROTECTED and side == -1:
			manifold.guard_mode[g] = SwordContactGeometry.GUARD_PASSING
			changed = true
	return changed


## Every touching point of the blades (from the last `_blade_distance`) as this
## tick's manifold, in the geometry's canonical order: where it lies, each
## blade fraction (crossguard → point) and its own normal. A later substep of
## the same tick replaces the record.
func _record_blade_points(manifold: SwordContactSet, touch: float) -> void:
	manifold.begin_substep()
	var index := 0
	for point in _geometry.count:
		if _geometry.point_gap[point] > touch:
			continue
		manifold.record_point(
			index,
			(_geometry.point_ax[point] + _geometry.point_bx[point]) * 0.5,
			(_geometry.point_ay[point] + _geometry.point_by[point]) * 0.5,
			_geometry.point_fraction_a[point],
			_geometry.point_fraction_b[point],
			_geometry.point_nx[point],
			_geometry.point_ny[point],
			_geometry.point_pair[point]
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
	var hx := _blade_x(attacker, weapon.blade_base_radius)
	var hy := _blade_y(attacker, weapon.blade_base_radius)
	var tx := _blade_x(attacker, weapon.tip_radius)
	var ty := _blade_y(attacker, weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, _frame[d + CENTER_X], _frame[d + CENTER_Y])
	report.body_x[attacker] = SimMath.mix(hx, tx, t)
	report.body_y[attacker] = SimMath.mix(hy, ty, t)
	return true


## Bisection steps that order a grip entry against steel inside one substep: a
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
## inside the grip) at which `attacker`'s blade entered the opponent's grip.
func _grip_entry(start: Array[FighterPose], finish: Array[FighterPose], attacker: int, from: float, to: float, rules: DuelRules) -> float:
	var outside := from
	var inside := to
	for _i in ENTRY_REFINEMENT:
		var middle := (outside + inside) * 0.5
		_interpolate(start, finish, middle, rules)
		if _grip_gap(attacker, rules) <= 0.0:
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


## Whether `attacker` may wound the opponent's grip this sweep: it can strike,
## its attack has not already struck a grip, and the opponent is a living
## fighter on the platform — the torso's rule. Only the blade wounds.
static func _grip_open(state: MatchState, attacker: int, can_strike: bool) -> bool:
	var target := state.opponent_of(attacker)
	return (
		can_strike
		and not state.fighter(attacker).weapon.grip_struck
		and target.is_alive()
		and not target.is_falling
	)


## The opponent's grip gap as the sweep reads it — only its sign and its
## crossing matter, so a grip certainly clear of `attacker`'s blade reads
## `GRIP_CLEAR` without measuring any part: every part of the grip region (the
## hands and the handle) lies within `grip_bound` of the handle's middle, so a
## blade farther than that (plus the blade's radius) from it is clear of all
## of them. Otherwise the exact gap (`_grip_gap`).
func _open_grip_gap(attacker: int, rules: DuelRules) -> float:
	var defending := rules.combatant(1 - attacker)
	var middle := defending.weapon.crossguard_centre_radius * 0.5
	var reach := grip_bound(defending) + rules.combatant(attacker).weapon.blade_radius
	if _blade_to_point(attacker, _blade_x(1 - attacker, middle), _blade_y(1 - attacker, middle), rules) > reach + CLEAR_MARGIN:
		return GRIP_CLEAR
	return _grip_gap(attacker, rules)


## The radius about the handle's middle (`crossguard_centre_radius / 2` down
## the blade) that encloses `spec`'s whole grip region: the handle and the
## hands on it, each with its own thickness.
static func grip_bound(spec: CombatantPhysicsSpec) -> float:
	var weapon := spec.weapon
	var half := weapon.crossguard_centre_radius * 0.5
	var hands := maxf(absf(weapon.offhand_grip_radius - half), absf(weapon.dominant_grip_radius - half))
	return maxf(half, hands) + maxf(spec.fighter.hand_radius, weapon.handle_radius)


## Surface gap from `attacker`'s blade to the nearest part of the opponent's
## grip region (GRIP-NONBLOCKING-001), each part as it is: the two hand discs
## (`hand_radius` about each grip marker) and the handle capsule (pommel to the
## crossguard's centre, `handle_radius`). The crossguard is not part of it: it
## passes through — neither steel nor hurt geometry. Records which part is
## nearest and the struck point on it in the opponent's sword frame (along,
## across). Parts within `PART_TIE` of each other are equally near and the one
## listed first is struck, so a blade lying parallel to the grip — level with
## both hands — strikes the same part in a scene and in its mirror or point
## reflection, whatever the rounding.
func _grip_gap(attacker: int, rules: DuelRules) -> float:
	var defending := rules.combatant(1 - attacker)
	var weapon := defending.weapon
	var blade := rules.combatant(attacker).weapon.blade_radius
	var d := 1 - attacker
	var off := weapon.offhand_grip_radius
	var dominant := weapon.dominant_grip_radius
	var least := _blade_to_point(attacker, _blade_x(d, off), _blade_y(d, off), rules) - defending.fighter.hand_radius - blade
	var struck := least
	_grip_source[attacker] = DuelEventKeys.SOURCE_HAND_OFF
	_grip_along[attacker] = off
	_grip_across[attacker] = 0.0
	var gap := _blade_to_point(attacker, _blade_x(d, dominant), _blade_y(d, dominant), rules) - defending.fighter.hand_radius - blade
	least = minf(least, gap)
	if gap < struck - PART_TIE:
		struck = gap
		_grip_source[attacker] = DuelEventKeys.SOURCE_HAND_DOMINANT
		_grip_along[attacker] = dominant
	var centre := weapon.crossguard_centre_radius
	if weapon.handle_radius > 0.0:
		gap = _blade_to_segment(attacker, _blade_x(d, 0.0), _blade_y(d, 0.0), _blade_x(d, centre), _blade_y(d, centre), rules) - weapon.handle_radius - blade
		least = minf(least, gap)
		if gap < struck - PART_TIE:
			struck = gap
			_grip_source[attacker] = DuelEventKeys.SOURCE_HANDLE
			_grip_along[attacker] = centre * _segment.t
			_grip_across[attacker] = 0.0
	return least


## Distance from `attacker`'s blade centre segment to the segment
## (`x0`, `y0`)–(`x1`, `y1`); the closest points are left in `_segment` (its
## `t` is the parameter on the given segment).
func _blade_to_segment(attacker: int, x0: float, y0: float, x1: float, y1: float, rules: DuelRules) -> float:
	var weapon := rules.combatant(attacker).weapon
	SimMath.closest_segments(
		_blade_x(attacker, weapon.blade_base_radius), _blade_y(attacker, weapon.blade_base_radius),
		_blade_x(attacker, weapon.tip_radius), _blade_y(attacker, weapon.tip_radius),
		x0, y0, x1, y1, _segment
	)
	return _segment.distance


## Distance from `attacker`'s blade centre segment to the point (`gx`, `gy`).
func _blade_to_point(attacker: int, gx: float, gy: float, rules: DuelRules) -> float:
	var weapon := rules.combatant(attacker).weapon
	var hx := _blade_x(attacker, weapon.blade_base_radius)
	var hy := _blade_y(attacker, weapon.blade_base_radius)
	var tx := _blade_x(attacker, weapon.tip_radius)
	var ty := _blade_y(attacker, weapon.tip_radius)
	var t := SimMath.closest_param_on_segment(hx, hy, tx, ty, gx, gy)
	return SimMath.length(gx - SimMath.mix(hx, tx, t), gy - SimMath.mix(hy, ty, t))


## Distance from attacker's blade to the defender's body center.
func _body_gap(attacker: int, weapon: WeaponDefinition) -> float:
	var d := (1 - attacker) * FRAME_STRIDE
	var hx := _blade_x(attacker, weapon.blade_base_radius)
	var hy := _blade_y(attacker, weapon.blade_base_radius)
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
