class_name MaterialCatalog
extends RefCounted

## Contact materials and how they meet (CONTACT-MATERIAL-001). Gameplay
## calibration, not engineering tables. Each call builds a fresh immutable
## definition (CONTENT-001).
##
## The first three are today's combat values moved here unchanged: steel
## restitution 0.35 above 1.4 m/s, steel on steel μ 0.20 (BLADE-FRICTION-001),
## a sword on a body μ 0.05 and e 0.02 (PHYS-010), body on body μ 0.30 and
## e 0.05 (PHYS-005). Stone and wood are the Arena's structures.
##
## See also: /docs/concepts/combat.md

const STEEL := &"material.steel"
const FLESH := &"material.flesh"
const STONE := &"material.stone"
const WOOD := &"material.wood"


static func steel() -> ContactMaterial:
	return ContactMaterial.create(STEEL, 0.35, 1.4, 0.2)


## A clothed body. Its own restitution only applies body to body.
static func flesh() -> ContactMaterial:
	return ContactMaterial.create(FLESH, 0.05, 0.0, 0.3)


static func stone() -> ContactMaterial:
	return ContactMaterial.create(STONE, 0.3, 1.4, 0.35)


static func wood() -> ContactMaterial:
	return ContactMaterial.create(WOOD, 0.15, 1.4, 0.45)


## The pairs every duel needs, authored so today's contact feel is exact.
static func standard_table() -> ContactMaterialTable:
	var table := ContactMaterialTable.new()
	table.define_pair(STEEL, STEEL, 0.2)
	table.define_pair(STEEL, FLESH, 0.05, 0.02)
	table.define_pair(FLESH, FLESH, 0.3, 0.05)
	## A blade on cut stone grips more than on steel and rings less; on a
	## wooden door it bites and barely rebounds. First values, to be felt.
	table.define_pair(STEEL, STONE, 0.35, 0.25)
	table.define_pair(STEEL, WOOD, 0.45, 0.1)
	return table
