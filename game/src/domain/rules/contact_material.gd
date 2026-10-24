class_name ContactMaterial
extends RefCounted

## One surface's own contact physics (CONTACT-MATERIAL-001): how elastic it is
## and how much it grips. Immutable authored content, like every definition
## (CONTENT-001). A weapon, a body, and a stage structure each carry one. A
## pair of materials is resolved once, at setup, by the rules' material table
## (`ContactMaterialTable`), never inside a solve.
##
## The physics is the solver's: `restitution` targets the separating speed of a
## new contact closing at least `restitution_threshold_speed` (m/s), and a
## slower one is inelastic, so slow and resting contacts never bounce
## (RIGID-CONTACT-002). `friction` is the Coulomb coefficient this surface
## brings to a pair the table has no entry for; there is one limit,
## `|Jt| ≤ μ·Jn`, which sticks or slides by itself. It is gameplay
## calibration, not a lookup of real steel or stone.
##
## Implements: /spec/invariants.md#contact-material-001
## See also: /docs/concepts/combat.md

var id: StringName = &""
var restitution: float = 0.0
var restitution_threshold_speed: float = 0.0
var friction: float = 0.0


static func create(material_id: StringName, elastic: float, threshold: float, grip: float) -> ContactMaterial:
	var material := ContactMaterial.new()
	material.id = material_id
	material.restitution = elastic
	material.restitution_threshold_speed = threshold
	material.friction = grip
	return material


## Restitution of a new contact of this surface closing at `closing` (m/s).
func restitution_at(closing: float) -> float:
	return restitution if closing >= restitution_threshold_speed else 0.0


func is_valid() -> bool:
	return (
		id != &""
		and is_finite(restitution) and restitution >= 0.0 and restitution <= 1.0
		and is_finite(restitution_threshold_speed) and restitution_threshold_speed >= 0.0
		and is_finite(friction) and friction >= 0.0 and friction <= 1.0
	)
