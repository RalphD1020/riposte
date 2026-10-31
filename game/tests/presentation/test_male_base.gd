extends "res://tests/presentation/test_production.gd"

## PRES-MALE-BASE: the male base, the authored master every male character derives from
## (CHARACTER-SOURCE-001), held to every PRES-PRODUCTION case unchanged —
## import and rig contract, clips, elbow, girdle, hip band, neck, and the real
## combat stack. The v1 candidate stays frozen under PRES-PRODUCTION.
##
## Implements: /spec/invariants.md#character-source-001
## See also: /docs/concepts/character-modeling.md, /docs/reference/assets.md
## Source: art-src/blender/characters/male_base.blend

const BASE_GLB := "res://assets/generated/characters/male_base.glb"
const BASE_WRAPPER := "res://assets/presentation/characters/male_base_wrapper.tscn"


func _init() -> void:
	suite_name = "PRES-MALE-BASE"


func _candidate_glb() -> String:
	return BASE_GLB


func _wrapper() -> String:
	return BASE_WRAPPER
