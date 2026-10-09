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
## Blade ribbon prominence, and sweet-region emphasis (`Off` 0 / `Standard` 1 /
## `Strong` above 1). Both scale how loudly the cue is drawn; neither widens the
## actual sweet region, changes damage, or changes timing (UX §54).
var trail_strength: float = 1.0
var sweet_spot_cue: float = 1.0
## Touch layout biases framing upward so thumbs do not cover the duel (UX §35).
var touch_layout: bool = false
## Show announcer lines as on-screen captions.
var captions: bool = true
## Particle count scale in [0, 1]. At 0 there are no particles and a hit is
## still marked by flash, sound, and pacing.
var particle_intensity: float = 1.0


func camera_impulses_enabled() -> bool:
	return screen_shake and not reduced_motion


func flash_scale() -> float:
	return RiposteTheme.REDUCED_FLASH_SCALE if reduced_flash else 1.0
