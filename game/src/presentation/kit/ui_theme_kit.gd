class_name UiThemeKit
extends Resource

## HUD and menu ornamentation variant, and the sounds menus make. Only accents
## and sounds live here; text and essential boundaries stay on `RiposteTheme`
## pairs so a theme can never break a tested contrast ratio (UX-001).
##
## See also: /docs/concepts/presentation.md

@export var theme_id: StringName = &""
@export var ornament: Color = RiposteTheme.GOLD_ACCENT
@export var ornament_shadow: Color = RiposteTheme.GOLD_SHADOW
## Short metallic/wooden UI takes, picked round-robin. Empty is silent.
@export var confirm: Array[AudioStream] = []
@export var back: Array[AudioStream] = []
@export var hover: Array[AudioStream] = []
