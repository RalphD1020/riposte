class_name PresentationOptions
extends RefCounted

## Accessibility and feel options the presentation honors (UX §51–§56).
## A plain value object so presentation never depends on how settings persist.
##
## See also: /docs/concepts/ux.md

var reduced_motion: bool = false
var reduced_flash: bool = false
var screen_shake: bool = true
var show_charge_indicator: bool = false
var high_contrast_weapons: bool = false
var haptics: bool = true
## Touch layout biases framing upward so thumbs do not cover the duel (UX §35).
var touch_layout: bool = false


func camera_impulses_enabled() -> bool:
	return screen_shake and not reduced_motion


func flash_scale() -> float:
	return RiposteTheme.REDUCED_FLASH_SCALE if reduced_flash else 1.0
