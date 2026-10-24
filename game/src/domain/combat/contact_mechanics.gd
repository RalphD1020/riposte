class_name ContactMechanics
extends RefCounted

## How a contact moves what it touches: the one home of contact effective
## mass, impulse and energy (IMPACT-PHYSICS-001). Every sword contact — blade
## on blade, blade into a body, the persistent sword-body constraint — is the
## same calculation, so how much of a hit moves a fighter, how much turns a
## sword, and how much energy the contact takes out all come from one place.
##
## A side holding a sword responds to an impulse `J` along a unit normal `n`
## at a point through two coordinates: its body (translation,
## `Δv = J / m_body`, the fighter's real mass) and its weapon angle θ
## (`Δθ̇ = J·c / M_θ`, `c` the weapon Jacobian on `n` —
## `WeaponKinematics.lever` — and `M_θ` the held sword's inertia, the hands
## riding the grip included). Its inverse effective mass is the sum,
## `1/m_body + c² / M_θ`; a struck body adds its own `1/m_body`. Mass answers
## how hard a body is to accelerate; how hard a fighter *tries* not to move is
## the bounded actuators' answer, never a substituted mass (rules v33). The
## contact's effective mass is the inverse of the sum over both sides, and
## from it
##
## ```text
## J      = (1 + e)·v_n / k        the impulse that removes the closing speed
## E_avail = ½·v_n² / k            what the contact could take out
## E_diss  = ½·(1 − e²)·v_n² / k   what it does take out
## ```
##
## Where a blade is struck changes only `c`: near the hands the lever
## vanishes and the bodies carry the contact; toward the tip the weapon term
## dominates and the sword turns. Strong and weak are that, not a multiplier.
## A point is no exception: driven straight along the blade its lever is the
## carriage's own `C′·n` (zero at Long Guard), so the sword barely turns;
## met off its axis the lever grows and the blade is deflected. Cut, poke and
## thrust are readings of one result, never separate mass models.
##
## Implements: /spec/invariants.md#impact-physics-001
## See also: /docs/concepts/combat.md


## The weapon coordinate's inertia at this pose for the combatant `spec`.
## Passive inertia is only what exists and where it sits: the sword's
## generalized inertia plus the hands riding the grip
## (`WeaponKinematics.held_inertia`). Being planted or committed does not
## change it — that is actuator force, motor torque and turn authority.
static func weapon_inertia(pose: BladePose, spec: CombatantPhysicsSpec) -> float:
	return WeaponKinematics.held_inertia(spec, pose)


## A held sword's two terms at a blade-on-blade point (`px`, `py`): its weapon
## coordinate's inertia into `out[0]` and its wielder's inverse body mass into
## `out[1]`, both the combatant `spec`'s own.
static func held_sword(_fighter: FighterState, pose: BladePose, _px: float, _py: float, spec: CombatantPhysicsSpec, out: PackedFloat64Array) -> void:
	out[0] = weapon_inertia(pose, spec)
	out[1] = body_inverse_mass(spec)


## Unit direction a contact point at offset `(rx, ry)` is travelling under
## angular velocity `omega`. A blade momentarily at rest still has an intended
## direction, so `fallback_dir` keeps the result total.
static func contact_tangent(rx: float, ry: float, omega: float, fallback_dir: float) -> PackedFloat64Array:
	var radius := SimMath.length(rx, ry)
	if radius <= SimMath.EPSILON:
		return PackedFloat64Array([0.0, 0.0])
	var turning := signf(omega) if absf(omega) > SimMath.EPSILON else fallback_dir
	return PackedFloat64Array([-ry / radius * turning, rx / radius * turning])


## A body's inverse mass in any contact — wielding, struck, or pushed. Always
## that fighter's own real mass: stance and footing decide how hard the
## actuators push back, never how much the body weighs.
static func body_inverse_mass(spec: CombatantPhysicsSpec) -> float:
	return 1.0 / spec.fighter.mass


## The impulse that removes `closing` (m/s, > 0) along the normal with
## restitution `e`, through inverse effective mass `inverse_mass`.
static func normal_impulse(closing: float, inverse_mass: float, restitution: float) -> float:
	return (1.0 + restitution) * closing / inverse_mass if inverse_mass > SimMath.EPSILON else 0.0


## The most energy the contact could take out of the closing motion (J).
static func available_energy(closing: float, inverse_mass: float) -> float:
	return 0.5 * closing * closing / inverse_mass if inverse_mass > SimMath.EPSILON else 0.0


## The energy the contact does take out with restitution `e` (J): the cutting,
## bruising, ringing share; what is left goes back into rebound.
static func dissipated_energy(closing: float, inverse_mass: float, restitution: float) -> float:
	return (1.0 - restitution * restitution) * available_energy(closing, inverse_mass)


## Distance down the blade from the pommel (m) of the sword's centre of
## percussion about the hands: `r = I_grip / (m·a)` from the middle of the two
## hands, `a` the centre of mass's distance from it. Struck there the sword
## turns about the hands without jarring them — a property of the weapon and
## the grip it is held with, not a bonus.
static func percussion_radius(weapon: WeaponDefinition) -> float:
	var grip := weapon.hand_centre_radius()
	var arm := weapon.center_of_mass_radius - grip
	if arm <= SimMath.EPSILON:
		return weapon.tip_radius
	var about_grip := weapon.moment_of_inertia() - weapon.mass * (2.0 * weapon.center_of_mass_radius * grip - grip * grip)
	return grip + about_grip / (weapon.mass * arm)


## The percussion radius as a blade fraction (0 = guard, 1 = tip).
static func percussion_fraction(weapon: WeaponDefinition) -> float:
	return SimMath.clamp01((percussion_radius(weapon) - weapon.blade_base_radius) / weapon.blade_length())


## The reference strike's inverse effective mass: `attacker`'s fully coupled,
## uncommitted blade struck at its centre of percussion from Long Guard,
## square to the blade, into `target`'s standing body. The injury calibration
## was seeded from this on the reference loadout (a witness, never a live
## normalizer), so normalized quantities keep their meaning whatever the
## contact model makes a kilogram.
static func reference_inverse_mass(attacker: CombatantPhysicsSpec, target: CombatantPhysicsSpec) -> float:
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, attacker, BladePose.new())
	return _reference_inverse_mass(attacker, target, pose, percussion_radius(attacker.weapon), -pose.uy, pose.ux)


## The reference thrust's inverse effective mass: the same wielder's tip from
## Long Guard driven straight along the blade into the same body.
## Same mechanics as the cut; along the axis the lever is only the carriage's.
static func reference_thrust_inverse_mass(attacker: CombatantPhysicsSpec, target: CombatantPhysicsSpec) -> float:
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, attacker, BladePose.new())
	return _reference_inverse_mass(attacker, target, pose, attacker.weapon.tip_radius, pose.ux, pose.uy)


static func _reference_inverse_mass(attacker: CombatantPhysicsSpec, target: CombatantPhysicsSpec, pose: BladePose, r: float, nx: float, ny: float) -> float:
	var lever := WeaponKinematics.lever(FighterState.new(), pose, pose.point_x(r), pose.point_y(r), nx, ny)
	var inertia := WeaponKinematics.held_inertia(attacker, pose)
	return body_inverse_mass(attacker) + body_inverse_mass(target) + lever * lever / inertia


## Impulse (N·s) of the reference strike at the attacker's weapon's reference
## closing speed.
## `pair` is the attacker's steel on the target's body.
static func reference_impulse(attacker: CombatantPhysicsSpec, target: CombatantPhysicsSpec, pair: ContactPair) -> float:
	var speed := attacker.weapon.reference_closing_speed
	return normal_impulse(speed, reference_inverse_mass(attacker, target), pair.restitution_at(speed))


## Energy (J) the reference strike dissipates.
static func reference_severity(attacker: CombatantPhysicsSpec, target: CombatantPhysicsSpec, pair: ContactPair) -> float:
	var speed := attacker.weapon.reference_closing_speed
	return dissipated_energy(speed, reference_inverse_mass(attacker, target), pair.restitution_at(speed))


## Energy (J) a reference strong clash dissipates: the two loadouts' swords
## met at their centres of percussion, square, closing at
## `blade_strong_speed` — the yardstick a clash's own dissipated energy is
## read against, from the same mechanics, so a clash reads as hard as the
## solve says it was.
## `pair` is the two swords' steel.
static func reference_clash_energy(a: CombatantPhysicsSpec, b: CombatantPhysicsSpec, pair: ContactPair, combat: CombatTuning) -> float:
	var k := (body_inverse_mass(a) + body_inverse_mass(b)) + (_clash_term(a) + _clash_term(b))
	var speed := combat.blade_strong_speed
	return dissipated_energy(speed, k, pair.restitution_at(speed))


## One sword's `c² / M_θ` at its centre of percussion from Long Guard.
static func _clash_term(spec: CombatantPhysicsSpec) -> float:
	var pose := WeaponKinematics.pose_at(0.0, 0.0, 0.0, 0.0, spec, BladePose.new())
	var r := percussion_radius(spec.weapon)
	var lever := WeaponKinematics.lever(FighterState.new(), pose, pose.point_x(r), pose.point_y(r), -pose.uy, pose.ux)
	return lever * lever / WeaponKinematics.held_inertia(spec, pose)


## Energy (J) the reference thrust dissipates at the reference closing speed:
## the right yardstick for a point, never the cut's, because along the blade
## almost nothing gives way but the bodies.
static func reference_thrust_severity(attacker: CombatantPhysicsSpec, target: CombatantPhysicsSpec, pair: ContactPair) -> float:
	var speed := attacker.weapon.reference_closing_speed
	return dissipated_energy(speed, reference_thrust_inverse_mass(attacker, target), pair.restitution_at(speed))
