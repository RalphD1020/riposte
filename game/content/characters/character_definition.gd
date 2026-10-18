class_name CharacterDefinition
extends RefCounted

## Typed character identity compiled from the character art file before a match
## starts. It names the fighter, the default weapon, and the handling. It does
## not own movement, contact, or a scene.
##
## See also: /docs/concepts/content.md

var id: StringName = &""
var display_name: String = ""
var body_scale: float = 1.0
var fighter_id: StringName = &""
var weapon_id: StringName = &""
var handling_id: StringName = &""


func is_reference_scale() -> bool:
	return is_equal_approx(body_scale, 1.0)
