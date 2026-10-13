class_name DamageModel
extends RefCounted

## The consequence half of a strike (COMBAT §51.2, §52–§54).
##
## `ImpactModel` has already decided what physically arrived. This file turns
## that physical severity into gameplay — damage, criticals, and the inputs
## stagger and displacement read.
##
## Damage reads the physics alone (v36): the energy the contact dissipated,
## scaled only by loss-only factors (where on the blade, edge or point
## alignment). How exposed the target was is a *reading* (`ExposureModel`),
## reported on the strike for the CPU, telemetry and presentation, and never a
## multiplier: a fighter who whiffs is punished because the opponent can hit
## them first, not because their flesh became softer. Criticals are
## convergence of physical quality, blade region and alignment, never chance.
##
## Implements: /spec/invariants.md#combat-003
## See also: /docs/concepts/combat.md


static func evaluate(attacker: FighterState, target: FighterState, point_x: float, point_y: float, rules: DuelRules) -> StrikeResult:
	return consequence(ImpactModel.resolve(attacker, target, point_x, point_y, rules), attacker, target, rules)


## Map one resolved impact onto its combat consequence. Taking the impact as
## an argument is what lets a chronological solver resolve contacts at their
## exact time of impact and still score them against pre-contact state.
static func consequence(impact: ImpactResult, attacker: FighterState, target: FighterState, rules: DuelRules) -> StrikeResult:
	var weapon := rules.spec_of(attacker).weapon
	var target_health := rules.spec_of(target).fighter.max_health
	var combat := rules.combat
	var strike := StrikeResult.new()
	strike.impact = impact
	strike.attacker = attacker.slot
	strike.target = target.slot
	var severity := minf(impact.normalized_severity(combat), combat.max_physical_quality)
	strike.contact_quality = SwingSemantics.contact_quality(impact.blade_efficiency, impact.edge_alignment, weapon)
	strike.physical_quality = severity * strike.contact_quality
	strike.exposure = ExposureModel.reading(target, attacker, rules)
	strike.exposure_fraction = strike.exposure
	strike.quality = strike.physical_quality
	strike.swing_potential = SwingSemantics.potential(
		SwingSemantics.tip_speed(attacker, rules.spec_of(attacker)),
		attacker.weapon.launch_readiness,
		attacker.stability,
		attacker.weapon.phase,
		weapon
	)
	strike.contact_kind = classify_contact(impact, attacker, rules)
	## Point strikes read the same contact energy as a cut, against the
	## thrust's own reference, scaled by loss-only factors: how squarely the
	## point enters (incidence) and the weapon's thrust efficiency. A point met
	## off its axis already delivered less, because the blade gave way. Same
	## damage curve, different reading.
	if strike.contact_kind == StrikeResult.ContactKind.POKE or strike.contact_kind == StrikeResult.ContactKind.THRUST:
		var point_quality := (impact.kinetic_severity / combat.reference_thrust_severity) * impact.incidence_quality * weapon.thrust_efficiency
		point_quality = minf(point_quality, combat.max_physical_quality)
		strike.physical_quality = point_quality
		strike.quality = point_quality
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
			strike.damage = target_health * combat.damage_scale
	elif strike.contact_kind == StrikeResult.ContactKind.THRUST:
		strike.lethal = true
		strike.damage = target_health * combat.damage_scale
	strike.stagger_pressure = impact.impulse / combat.reference_impulse
	strike.critical = (
		strike.physical_quality >= combat.critical_quality
		and impact.blade_fraction >= combat.critical_blade_min
		and impact.blade_fraction <= combat.critical_blade_max
		and impact.edge_alignment >= combat.critical_alignment
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
	var weapon := rules.spec_of(attacker).weapon
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
