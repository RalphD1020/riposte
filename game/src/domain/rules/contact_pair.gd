class_name ContactPair
extends RefCounted

## Two materials as one contact sees them, resolved once by the rules'
## `ContactMaterialTable` (CONTACT-MATERIAL-001). The solver reads `friction`
## and `restitution_at` and nothing else: no id, no table, no string in a solve.
##
## Restitution: an authored pair value when the table has one, otherwise the
## less elastic of the two surfaces, each with its own threshold — so a soft
## surface never rings like steel, and two of the same surface are exactly
## that surface.
##
## See also: /docs/concepts/combat.md

var a: ContactMaterial
var b: ContactMaterial
var friction: float = 0.0
## NAN when the pair takes the less elastic surface.
var restitution_override: float = NAN


func restitution_at(closing: float) -> float:
	if not is_nan(restitution_override):
		return restitution_override
	return minf(a.restitution_at(closing), b.restitution_at(closing))


## The most elastic this pair can ever be (for bounds, never for a solve).
func restitution_bound() -> float:
	if not is_nan(restitution_override):
		return restitution_override
	return minf(a.restitution, b.restitution)
