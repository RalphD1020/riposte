extends "res://tests/presentation/test_production.gd"

## PRES-MALE-BASE-HEAVY-HALF: The male base in its "heavy_half" physique configuration
## (art-src/blender/characters/male_base.configuration.json), baked by
## the export, held to every PRES-PRODUCTION case unchanged. The configuration
## range is production-ready only if its ends and its middle all pass.
##
## Implements: /spec/invariants.md#character-source-001
## See also: /docs/concepts/character-modeling.md, /docs/reference/assets.md
## Source: art-src/blender/characters/male_base.blend

const VARIANT_GLB := "res://assets/generated/characters/variants/male_base_heavy_half.glb"
const VARIANT_WRAPPER := "res://assets/presentation/characters/male_base_heavy_half_wrapper.tscn"


func _init() -> void:
	suite_name = "PRES-MALE-BASE-HEAVY-HALF"


func _candidate_glb() -> String:
	return VARIANT_GLB


func _wrapper() -> String:
	return VARIANT_WRAPPER
