class_name StrikeResult
extends RefCounted

## Everything that happened at one body contact (COMBAT §51–§55), evaluated
## before any effect is applied so double hits stay symmetric.
##
## Two layers, deliberately: `impact` is the physics that arrived, and the
## fields beside it are the combat consequence drawn from it. Consumers that
## want to know *why* a hit felt the way it did read `impact`; consumers that
## just need the verdict read `quality` and `damage`.
##
## See also: /docs/concepts/combat.md

var attacker: int = -1
var target: int = -1
## When inside the tick this landed, as a fraction in [0, 1]. The chronological
## solver stamps it so a trade can be attributed to whoever struck first.
var toi: float = 0.0
## What physically arrived. Never null for a strike produced by the resolver.
var impact: ImpactResult = ImpactResult.new()
## Physical severity before the target's ability to cope with it.
var physical_quality: float = 0.0
## How dangerous the swing was in the abstract, at the instant it connected.
## Diagnostic only: the energy it actually delivered is already in `impact`,
## so this never multiplies into damage — it is here so feedback and telemetry
## can say *why* a hit landed the way it did (COMBAT-009).
var swing_potential: float = 0.0
## How well the contact geometry served the strike: the right part of the
## blade, led by the edge.
var contact_quality: float = 0.0
## How incapable the target was of responding, read from pre-contact state.
var exposure: float = 0.0
## The same exposure as a bounded [0, 1] reading, for consumers that want
## "how exposed" rather than a multiplier.
var exposure_fraction: float = 0.0
## `physical_quality × exposure`: the gameplay consequence, and the only place
## exposure participates (PHYS-004).
var quality: float = 0.0
var damage: float = 0.0
## Normalized impulse scaled by how susceptible the target was to being
## unbalanced. Drives stagger. Separate from `quality` because a heavy shove
## and a deep cut are different events (PHYS-004).
var stagger_pressure: float = 0.0
var critical: bool = false
## What this hit *was*, named. Describes the result; never chooses it.
var grade: SwingSemantics.Grade = SwingSemantics.Grade.GRAZE

## Body-contact classification (COMBAT-010). Determined at contact from
## geometry, never from input. SLASH is the default sweep. POKE is a
## point-first contact during normal movement. THRUST is a point-first
## contact with forward burst and sword-to-motion alignment. GRAZE is a
## glancing contact below the quality threshold. Classification describes
## how the contact arose. One physical severity model for all kinds; the
## lethality law (COMBAT-011) diverges by classification on top of it.
enum ContactKind { SLASH, POKE, THRUST, GRAZE }
var contact_kind: ContactKind = ContactKind.SLASH
## Whether the lethality law (COMBAT-011) determined this strike is an
## instant kill. True for unprotected THRUSTs (no prior blade defense) and
## POKEs whose physical severity reaches the lethal threshold.
var lethal: bool = false
## Whether the contact geometry satisfies the stabbing-angle predicate
## (PHYS-008). True for point-first entry with sufficient axial alignment
## and incidence. Controls blade reaction suppression, not classification.
var is_stabbing: bool = false


func to_payload() -> Dictionary:
	var kind_label := "slash"
	if contact_kind == ContactKind.POKE:
		kind_label = "poke"
	elif contact_kind == ContactKind.THRUST:
		kind_label = "thrust"
	elif contact_kind == ContactKind.GRAZE:
		kind_label = "graze"
	return {
		DuelEventKeys.X: impact.point_x,
		DuelEventKeys.Y: impact.point_y,
		DuelEventKeys.DAMAGE: damage,
		DuelEventKeys.QUALITY: quality,
		DuelEventKeys.PHYSICAL_QUALITY: physical_quality,
		DuelEventKeys.SWING_POTENTIAL: swing_potential,
		DuelEventKeys.CONTACT_QUALITY: contact_quality,
		DuelEventKeys.EXPOSURE: exposure,
		DuelEventKeys.EXPOSURE_FRACTION: exposure_fraction,
		DuelEventKeys.GRADE: SwingSemantics.grade_label(grade),
		DuelEventKeys.CLOSING_SPEED: impact.normal_speed,
		DuelEventKeys.NORMAL_X: impact.normal_x,
		DuelEventKeys.NORMAL_Y: impact.normal_y,
		DuelEventKeys.STRIKE_X: impact.strike_x,
		DuelEventKeys.STRIKE_Y: impact.strike_y,
		DuelEventKeys.PUSH: impact.target_delta_v(),
		DuelEventKeys.BLADE_FRACTION: impact.blade_fraction,
		DuelEventKeys.ALIGNMENT: impact.edge_alignment,
		DuelEventKeys.COUPLING: impact.coupling,
		DuelEventKeys.EFFECTIVE_MASS: impact.attacker_effective_mass,
		DuelEventKeys.IMPULSE: impact.impulse,
		DuelEventKeys.SEVERITY: impact.kinetic_severity,
		DuelEventKeys.STAGGER_PRESSURE: stagger_pressure,
		DuelEventKeys.CRITICAL: critical,
		DuelEventKeys.LETHAL: lethal,
		DuelEventKeys.CONTACT_KIND: kind_label,
		DuelEventKeys.TOI: toi,
	}
