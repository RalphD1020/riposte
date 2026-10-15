class_name ImpactModel
extends RefCounted

## The physical half of a strike (COMBAT §34–§36A, §51.1): what actually
## arrived at the contact point.
##
## Both fighters participate. The blade's velocity is the sum of its motions —
## the fighter translating, the fighter rotating, the weapon rotating, and the
## origin riding its attack path (`WeaponKinematics`) — and what matters is that
## velocity *relative to the target*, projected on the contact normal:
##
## ```text
## v_blade = v_fighter + ω_body × r + ω_weapon × r + θ̇·(R·P′ − perp(origin − X))
## v_rel   = v_blade - v_target
## v_n     = -v_rel · n̂
## ```
##
## So the same swing is harder against an advancing target and softer against
## a retreating one, with no movement state carrying a damage modifier
## (PHYS-001). Impulse and energy come from the contact's effective mass
## (`ContactMechanics`), so where on the blade it landed, how the carriage was
## moving and how the body was coupled all reach the result through physics,
## never a multiplier. Charge reaches it only through the velocity the motor
## built. Nothing in this file reads health, exposure, or anything about the
## target's ability to respond (PHYS-004).
##
## Implements: /spec/invariants.md#phys-001
## Implements: /spec/invariants.md#impact-physics-001
## See also: /docs/concepts/combat.md


static func resolve(attacker: FighterState, target: FighterState, point_x: float, point_y: float, rules: DuelRules) -> ImpactResult:
	return resolve_at(attacker, point_x, point_y, target.x, target.y, target.vx, target.vy, rules.spec_of(target).fighter.mass, rules)


## The same impact against any hurt shape of `target`: its centre (the normal
## points into it), the velocity of its surface, and the effective mass it
## answers with — the torso's body, or the held sword at the struck grip point
## (GRIP-NONBLOCKING-001), so a grip moving with its sword is struck at its own
## speed, never as a still point of the torso.
static func resolve_at(attacker: FighterState, point_x: float, point_y: float, centre_x: float, centre_y: float, target_vx: float, target_vy: float, target_mass: float, rules: DuelRules) -> ImpactResult:
	var wielding := rules.spec_of(attacker)
	var weapon := wielding.weapon
	var combat := rules.combat
	var impact := ImpactResult.new()
	impact.point_x = point_x
	impact.point_y = point_y

	var pose := WeaponKinematics.pose_of(attacker, wielding, BladePose.new())
	## Down the blade from its origin (the body centre on a fixed path).
	var bx := point_x - pose.origin_x
	var by := point_y - pose.origin_y
	var radius := SimMath.length(bx, by)
	impact.blade_fraction = SimMath.clamp01((radius - weapon.blade_base_radius) / weapon.blade_length())

	## Body rotation and weapon rotation both turn the contact point about the
	## fighter, so they add; the attack path adds its own share on top.
	var omega := attacker.turn_rate + attacker.weapon.speed
	WeaponKinematics.velocity_into(attacker, pose, point_x, point_y)
	var relative_x := pose.vx - target_vx
	var relative_y := pose.vy - target_vy
	impact.relative_speed = SimMath.length(relative_x, relative_y)

	var blade_x := bx / radius if radius > SimMath.EPSILON else pose.ux
	var blade_y := by / radius if radius > SimMath.EPSILON else pose.uy
	var turning := signf(omega) if absf(omega) > SimMath.EPSILON else attacker.weapon.swing_dir
	impact.strike_x = -blade_y * turning
	impact.strike_y = blade_x * turning

	var to_center_x := centre_x - point_x
	var to_center_y := centre_y - point_y
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

	impact.coupling = StructuralCoupling.coupling(attacker, impact.strike_x, impact.strike_y, wielding.fighter, combat)
	impact.attacker_mass = wielding.fighter.mass
	impact.target_mass = target_mass

	## Point-strike kinematics (COMBAT-010, PHYS-007). Axial speed is the
	## relative velocity projected along the sword axis (blade_x, blade_y).
	## A positive value means the point is moving toward the target.
	impact.axial_speed = maxf(0.0, relative_x * blade_x + relative_y * blade_y)
	impact.transverse_speed = absf(relative_x * impact.strike_x + relative_y * impact.strike_y)
	impact.tangent_speed = absf(-relative_x * impact.normal_y + relative_y * impact.normal_x)
	if impact.relative_speed > SimMath.EPSILON:
		impact.thrust_alignment = impact.axial_speed / impact.relative_speed
	## Incidence quality: how directly the point enters the body surface.
	## The impact normal points toward the target center, so `â · n̂` is
	## positive when the blade aims into the body (head-on).
	impact.incidence_quality = maxf(0.0, blade_x * impact.normal_x + blade_y * impact.normal_y)

	## One contact, one effective mass (IMPACT-PHYSICS-001): the target's body,
	## the attacker's body, and the held weapon coordinate turning back
	## through its lever — for a cut and a point alike. A point
	## driven along its blade has almost no lever and turns nothing; met off
	## its axis it gives way. Momentum and energy of the same event come out
	## of it; both are needed because they drive different consequences
	## (COMBAT §36A).
	impact.lever_cross = WeaponKinematics.lever(attacker, pose, point_x, point_y, impact.normal_x, impact.normal_y)
	impact.weapon_inertia = ContactMechanics.weapon_inertia(pose, wielding)
	var bodies := 1.0 / impact.attacker_mass + 1.0 / impact.target_mass
	impact.inverse_effective_mass = bodies + impact.lever_cross * impact.lever_cross / impact.weapon_inertia
	impact.restitution = combat.sword_body_restitution
	impact.impulse = ContactMechanics.normal_impulse(impact.normal_speed, impact.inverse_effective_mass, impact.restitution)
	impact.available_energy = ContactMechanics.available_energy(impact.normal_speed, impact.inverse_effective_mass)
	impact.kinetic_severity = ContactMechanics.dissipated_energy(impact.normal_speed, impact.inverse_effective_mass, impact.restitution)
	return impact
