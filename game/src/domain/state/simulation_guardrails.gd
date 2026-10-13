class_name SimulationGuardrails
extends RefCounted

## Minimal cross-cutting runtime safeguards that do not belong in existing
## single-owner modules. This is NOT a facade over StateInvariants,
## DuelRules.is_valid(), or CombatTuning — those stay in their own homes.
##
## Implements: /spec/invariants.md#sim-001
## See also: /docs/concepts/simulation.md


## Tolerance for TOI monotonicity in normalized tick-fraction space.
const TOI_EPSILON := 1e-12

## Safety factor applied to authored maximums when computing impossibility
## bounds. A corrupted state that looks valid is worse than a no-contest.
const CAPACITY_SAFETY_FACTOR := 2.0


## Asserts that a newly computed TOI has not regressed behind the current
## elapsed fraction. Returns true when valid. A violation means the contact
## solver would process events out of chronological order.
static func validate_toi_monotonicity(elapsed: float, new_toi: float) -> bool:
	return new_toi >= elapsed - TOI_EPSILON


## Returns true when a fighter's physical velocities are within the
## impossibility bounds derived from authored maximums. A violation means the
## state is corrupted beyond any legal sequence of commands.
##
## The weapon has two speeds that must not be confused. The motor never drives
## it past `swing_speed_full` (the actuated limit); a contact can legally knock
## it far faster — a dash into the opponent's hilt whips a blade away — so the
## corruption bound is the physically valid one,
## `physical_weapon_speed_bound`, never the actuated one.
static func validate_capacity(fighter: FighterState, rules: DuelRules) -> bool:
	var spec := rules.spec_of(fighter)
	var opponent := rules.combatant(1 - fighter.slot)
	var body_limit := max_body_speed(spec.fighter) * CAPACITY_SAFETY_FACTOR
	if fighter.speed() > body_limit:
		return false
	## A non-finite speed is `StateInvariants`' to name; these comparisons are
	## false for NaN, so it passes through to that check.
	var spin := absf(fighter.weapon.speed)
	if spin > spec.weapon.swing_speed_full * CAPACITY_SAFETY_FACTOR and spin > physical_weapon_speed_bound(spec, opponent) * CAPACITY_SAFETY_FACTOR:
		return false
	return true


## The fastest the weapon coordinate can legally turn (rad/s): the motor's
## full swing plus the largest kick one held-sword contact can give
## (SwordContactSolver). Each wielder's body shares a contact's impulse, so the
## weapon's share `Δθ̇ = J·c/M` over `K = Σc²/M + Σ1/m` peaks at
## `(1 + e)·v / (2·√(M·Σ1/m))`. `M` is the weapon coordinate's one inertia
## (UNIFIED-MASS-001), bounded below at every pose by the sword's own inertia
## about its centre of mass (completing the square in the generalized
## inertia). The hands only add inertia, so they cannot make a legal kick
## larger than this; plant and commitment are not in `M`. `v` is bounded by
## each contact point moving at its own fighter's full body speed plus a full
## swing at its own farthest blade point; `e` is the livelier of the two
## weapons. `spec` is the sword's own combatant, `opponent` the other.
static func physical_weapon_speed_bound(spec: CombatantPhysicsSpec, opponent: CombatantPhysicsSpec) -> float:
	var weapon := spec.weapon
	var centroidal := maxf(weapon.moment_of_inertia() - weapon.mass * weapon.center_of_mass_radius * weapon.center_of_mass_radius, SimMath.EPSILON)
	var inertia := centroidal
	var closing := _contact_speed(spec) + _contact_speed(opponent)
	var bodies := 1.0 / spec.fighter.mass + 1.0 / opponent.fighter.mass
	var restitution := maxf(weapon.restitution, opponent.weapon.restitution)
	return weapon.swing_speed_full + (1.0 + restitution) * closing / (2.0 * sqrt(inertia * bodies))


## The fastest one side's contact point can move: its body at full speed plus
## its full swing at the farthest blade point.
static func _contact_speed(spec: CombatantPhysicsSpec) -> float:
	var path := spec.handling.attack_path
	var farthest := spec.weapon.tip_radius + absf(path.carriage_forward(0.0)) + absf(path.carriage_left(path.limit()))
	return max_body_speed(spec.fighter) + spec.weapon.swing_speed_full * farthest


## The fastest `body` can legally move under its own actuators (m/s).
static func max_body_speed(body: FighterDefinition) -> float:
	return maxf(body.max_speed, maxf(body.burst_speed_axial, body.burst_speed_lateral))


## Diagnostic-only: logs impossible command transitions. Not a simulation
## fault — the caller decides whether to log or ignore.
static func diagnose_command(cmd: PlayerCommand) -> String:
	if cmd.attack_released and not cmd.attack_pressed:
		if cmd.attack_cancel:
			return ""
	return ""
