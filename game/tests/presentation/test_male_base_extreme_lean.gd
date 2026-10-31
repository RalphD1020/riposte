extends "res://tests/presentation/test_production.gd"

## PRES-MALE-BASE-EXTREME-LEAN: The male base in its "extreme_lean" physique configuration
## (art-src/blender/characters/male_base.configuration.json), baked by
## the export, held to every PRES-PRODUCTION case unchanged. The configuration
## range is production-ready only if its ends and its middle all pass.
##
## Implements: /spec/invariants.md#character-source-001
## See also: /docs/concepts/character-modeling.md, /docs/reference/assets.md
## Source: art-src/blender/characters/male_base.blend

const VARIANT_GLB := "res://assets/generated/characters/variants/male_base_extreme_lean.glb"
const VARIANT_WRAPPER := "res://assets/presentation/characters/male_base_extreme_lean_wrapper.tscn"


func _init() -> void:
	suite_name = "PRES-MALE-BASE-EXTREME-LEAN"


func _candidate_glb() -> String:
	return VARIANT_GLB


func _wrapper() -> String:
	return VARIANT_WRAPPER
