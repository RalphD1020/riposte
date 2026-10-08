class_name ImpactModel
extends RefCounted

## The physical half of a strike (COMBAT §34–§36A, §51.1): what actually
## arrived at the contact point.
##
## Both fighters participate. The blade's velocity is the sum of three
## motions — the fighter translating, the fighter rotating, and the weapon
## rotating about the pivot — and what matters is that velocity *relative to
## the target*, projected on the contact normal:
##
## ```text
## v_blade = v_fighter + ω_body × r_pivot + ω_weapon × r_blade
## v_rel   = v_blade - v_target
## v_n     = -v_rel · n̂
## ```
##
## So the same swing is harder against an advancing target and softer against
## a retreating one, with no movement state carrying a damage modifier
## (PHYS-001). Nothing in this file reads health, exposure, or anything about
## the target's ability to respond (PHYS-004).
##
## Implements: /spec/invariants.md#phys-001
## See also: /docs/concepts/combat.md


static func resolve(attacker: FighterState, target: FighterState, point_x: float, point_y: float, rules: DuelRules) -> ImpactResult:
	var weapon := rules.weapon
	var combat := rules.combat
	var impact := ImpactResult.new()
	impact.point_x = point_x
	impact.point_y = point_y

	var rx := point_x - attacker.x
	var ry := point_y - attacker.y
	var radius := SimMath.length(rx, ry)
	impact.blade_fraction = SimMath.clamp01((radius - weapon.hilt_radius) / weapon.blade_length())

	## Body rotation and weapon rotation both turn the contact point about the
	## same pivot, so they add.
	var omega := attacker.turn_rate + attacker.weapon.speed
	var relative_x := attacker.vx - omega * ry - target.vx
	var relative_y := attacker.vy + omega * rx - target.vy
	impact.relative_speed = SimMath.length(relative_x, relative_y)

	var blade_x := rx / radius if radius > SimMath.EPSILON else SimMath.cosine(DuelGeometry.blade_angle(attacker))
	var blade_y := ry / radius if radius > SimMath.EPSILON else SimMath.sine(DuelGeometry.blade_angle(attacker))
	var turning := signf(omega) if absf(omega) > SimMath.EPSILON else attacker.weapon.swing_dir
	impact.strike_x = -blade_y * turning
	impact.strike_y = blade_x * turning

	var to_center_x := target.x - point_x
	var to_center_y := target.y - point_y
	var center_distance := SimMath.length(to_center_x, to_center_y)
	if center_distance > SimMath.EPSILON:
		impact.normal_x = to_center_x / center_distance
		impact.normal_y = to_center_y / center_distance
	else:
		impact.normal_x = impact.strike_x
		impact.normal_y = impact.strike_y
	impact.normal_speed = maxf(0.0, relative_x * impact.normal_x + relative_y * impact.normal_y)

	impact.blade_efficiency = weapon.efficiency(impact.blade_fraction)
	if impact.relative_speed > SimMath.EPSILON:
		impact.edge_alignment = SimMath.clamp01(
			(relative_x * impact.strike_x + relative_y * impact.strike_y) / impact.relative_speed
		)

	impact.coupling = StructuralCoupling.coupling(attacker, impact.strike_x, impact.strike_y, rules.fighter, combat)
	impact.attacker_effective_mass = StructuralCoupling.effective_mass(impact.coupling, rules)
	impact.target_effective_mass = StructuralCoupling.resisting_mass(target, rules.fighter, combat)

	## Momentum and energy of the same event. Both are needed because they
	## drive different consequences (COMBAT §36A).
	impact.impulse = impact.attacker_effective_mass * impact.normal_speed
	impact.kinetic_severity = 0.5 * impact.attacker_effective_mass * impact.normal_speed * impact.normal_speed

	## Point-strike kinematics (COMBAT-010, PHYS-007). Axial speed is the
	## relative velocity projected along the sword axis (blade_x, blade_y).
	## A positive value means the point is moving toward the target.
	impact.axial_speed = maxf(0.0, relative_x * blade_x + relative_y * blade_y)
	if impact.relative_speed > SimMath.EPSILON:
		impact.thrust_alignment = impact.axial_speed / impact.relative_speed
	## Incidence quality: how directly the point enters the body surface.
	## The impact normal points toward the target center, so `â · n̂` is
	## positive when the blade aims into the body (head-on).
	impact.incidence_quality = maxf(0.0, blade_x * impact.normal_x + blade_y * impact.normal_y)

	## Bilateral impulse (PHYS-010). The inverse effective mass scalar k
	## includes both body masses and the weapon's angular inertia at the
	## contact lever arm. For stabbing contacts, the angular term is excluded
	## because the blade penetrates cleanly. The is_stabbing flag is set later
	## by DamageModel, so we compute the full k here; the resolver adjusts if
	## the contact is classified as stabbing.
	impact.lever_cross = rx * impact.normal_y - ry * impact.normal_x
	var weapon_moi := weapon.moment_of_inertia()
	var inv_k := 0.0
	if impact.target_effective_mass > SimMath.EPSILON:
		inv_k += 1.0 / impact.target_effective_mass
	if impact.attacker_effective_mass > SimMath.EPSILON:
		inv_k += 1.0 / impact.attacker_effective_mass
	if weapon_moi > SimMath.EPSILON:
		inv_k += impact.lever_cross * impact.lever_cross / weapon_moi
	impact.inverse_effective_mass = inv_k
	if inv_k > SimMath.EPSILON:
		impact.bilateral_impulse = impact.normal_speed / inv_k
	return impact
