class_name DamageModel
extends RefCounted

## The consequence half of a strike (COMBAT §47, §51.2, §52–§54).
##
## `ImpactModel` has already decided what physically arrived. This file does
## the other, separate job: decide how badly the target was positioned to deal
## with it, and turn physical severity into gameplay — damage, criticals, and
## the inputs stagger and displacement read.
##
## The separation is load-bearing (PHYS-004). Exposure modifies *consequence*;
## it never fabricates incoming energy or momentum, and it is read from target
## state before contact so a hit can never amplify itself. Criticals are
## convergence, never chance.
##
## Implements: /spec/invariants.md#combat-003
## See also: /docs/concepts/combat.md


static func evaluate(attacker: FighterState, target: FighterState, point_x: float, point_y: float, rules: DuelRules) -> StrikeResult:
	return consequence(ImpactModel.resolve(attacker, target, point_x, point_y, rules), attacker, target, rules)


## Map one resolved impact onto its combat consequence. Taking the impact as
## an argument is what lets a chronological solver resolve contacts at their
## exact time of impact and still score them against pre-contact state.
static func consequence(impact: ImpactResult, attacker: FighterState, target: FighterState, rules: DuelRules) -> StrikeResult:
	var weapon := rules.weapon
	var combat := rules.combat
	var strike := StrikeResult.new()
	strike.impact = impact
	strike.attacker = attacker.slot
	strike.target = target.slot
	var severity := minf(impact.normalized_severity(combat), combat.max_physical_quality)
	strike.contact_quality = SwingSemantics.contact_quality(impact.blade_efficiency, impact.edge_alignment, weapon)
	strike.physical_quality = severity * strike.contact_quality
	strike.exposure = exposure(target, attacker, rules)
	strike.exposure_fraction = SwingSemantics.exposure_fraction(strike.exposure, combat)
	strike.quality = strike.physical_quality * strike.exposure
	strike.swing_potential = SwingSemantics.potential(
		SwingSemantics.tip_speed(attacker, weapon),
		attacker.weapon.launch_readiness,
		attacker.stability,
		attacker.weapon.phase,
		weapon
	)
	strike.contact_kind = classify_contact(impact, attacker, rules)
	strike.is_stabbing = is_stabbing_angle(impact, rules)
	## Point strikes use axial severity: the kinetic energy in the forward
	## component of the contact, modulated by incidence quality and the
	## weapon's thrust efficiency. Same damage curve, different input.
	if strike.contact_kind == StrikeResult.ContactKind.POKE or strike.contact_kind == StrikeResult.ContactKind.THRUST:
		var axial_severity := 0.5 * impact.attacker_effective_mass * impact.axial_speed * impact.axial_speed
		var point_quality := (axial_severity / combat.reference_severity) * impact.incidence_quality * weapon.thrust_efficiency
		point_quality = minf(point_quality, combat.max_physical_quality)
		strike.physical_quality = point_quality
		strike.quality = point_quality * strike.exposure
	strike.damage = combat.damage_for(strike.quality)
	## Lethality law (COMBAT-011). One physical severity model for base
	## evaluation; lethality diverges by classification on top of it.
	## POKE at or above the lethal threshold → instant kill.
	## THRUST (burst-aligned point entry) → always instant kill. Defense is
	## handled by the chronological TOI solver, not a persisted flag: if a
	## blade contact redirected the weapon trajectory, either the thrust
	## classification no longer qualifies or the physics says the point
	## still drove through.
	if strike.contact_kind == StrikeResult.ContactKind.POKE:
		if strike.physical_quality >= combat.poke_lethal_quality:
			strike.lethal = true
			strike.damage = rules.fighter.max_health * combat.damage_scale
	elif strike.contact_kind == StrikeResult.ContactKind.THRUST:
		strike.lethal = true
		strike.damage = rules.fighter.max_health * combat.damage_scale
	strike.stagger_pressure = impact.normalized_impulse(combat) * strike.exposure
	strike.critical = (
		strike.physical_quality >= combat.critical_quality
		and impact.blade_fraction >= combat.critical_blade_min
		and impact.blade_fraction <= combat.critical_blade_max
		and impact.edge_alignment >= combat.critical_alignment
		and strike.exposure >= combat.critical_exposure
	)
	strike.grade = SwingSemantics.grade(strike.quality, strike.critical)
	return strike


## Classify a body contact as SLASH, POKE, THRUST, or GRAZE (COMBAT-010).
## Classification is purely geometric — it describes how the contact arose.
## Severity affects damage, not classification. GRAZE means tangential/glancing
## geometry, not low energy. The lethality law (COMBAT-011) diverges by
## classification on top of the shared severity model.
static func classify_contact(impact: ImpactResult, attacker: FighterState, rules: DuelRules) -> StrikeResult.ContactKind:
	var combat := rules.combat
	var weapon := rules.weapon
	## Point-strike candidate: tip region, sufficient axial alignment,
	## sufficient incidence. Severity is NOT a gate — a weak aligned tip
	## contact is a weak POKE, not a GRAZE (COMBAT-010).
	if (
		weapon.supports_thrust
		and impact.blade_fraction >= weapon.tip_region_start
		and impact.thrust_alignment >= combat.point_strike_alignment
		and impact.incidence_quality >= combat.point_strike_incidence
	):
		## THRUST: all POKE criteria plus an active burst aligned to the sword.
		if attacker.gesture.is_bursting():
			var blade_angle := DuelGeometry.blade_angle(attacker)
			var sword_x := SimMath.cosine(blade_angle)
			var sword_y := SimMath.sine(blade_angle)
			var burst_dot := attacker.gesture.burst_dir_x * sword_x + attacker.gesture.burst_dir_y * sword_y
			if burst_dot >= combat.thrust_burst_alignment:
				return StrikeResult.ContactKind.THRUST
		return StrikeResult.ContactKind.POKE
	## Non-point-strike: check contact geometry for GRAZE vs SLASH.
	## GRAZE means glancing/tangential — the edge did not lead the contact.
	var cq := SwingSemantics.contact_quality(impact.blade_efficiency, impact.edge_alignment, weapon)
	if cq < combat.graze_quality:
		return StrikeResult.ContactKind.GRAZE
	return StrikeResult.ContactKind.SLASH


## Stabbing-angle predicate (PHYS-008). Exactly the same geometry check as
## point-strike classification — tip region, sufficient alignment, sufficient
## incidence. If the contact geometry is point-first enough to be a POKE, it
## is also point-first enough for the blade to penetrate without reaction.
## There is intentionally one definition, not two: if stabbing geometry
## and classification ever diverged, a contact could suppress blade reaction
## without being classified as a point strike, which is incoherent.
static func is_stabbing_angle(impact: ImpactResult, rules: DuelRules) -> bool:
	return (
		impact.blade_fraction >= rules.weapon.tip_region_start
		and impact.thrust_alignment >= rules.combat.point_strike_alignment
		and impact.incidence_quality >= rules.combat.point_strike_incidence
	)


## Vulnerability is relational state, not a flat "attacking = +X% damage"
## (COMBAT §47): commitment, balance debt, being out-angled, and the phase
## the target is caught in.
##
## Heavy attacks expose their owner because they cannot correct geometry, not
## because a multiplier is applied to them.
static func exposure(target: FighterState, attacker: FighterState, rules: DuelRules) -> float:
	var combat := rules.combat
	var value := combat.exposure_base
	value += combat.exposure_commit * target.weapon.commitment
	value += combat.exposure_balance * (1.0 - target.stability)
	value += combat.exposure_flank * absf(DuelGeometry.facing_error(target, attacker)) / PI
	match target.weapon.phase:
		CombatPhase.Id.CHARGING:
			value += combat.exposure_charging
		CombatPhase.Id.OVERSWING:
			value += combat.exposure_overswing
		CombatPhase.Id.RECOVERY:
			value += combat.exposure_recovery
		CombatPhase.Id.STAGGER:
			value += combat.exposure_stagger
	return clampf(value, combat.exposure_min, combat.exposure_max)
