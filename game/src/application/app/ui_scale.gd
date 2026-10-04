class_name UiScale
extends RefCounted

## Keeps one UI unit ≥ one CSS pixel, so RiposteTheme sizes (48 px targets,
## 16 px text) mean on a phone what they mean on the website. `canvas_items`
## stretch from the 1280×720 base alone would shrink a landscape phone's
## 48-unit target to ~25 CSS px (UX §36). Also caps 3D rendering at 2× CSS
## resolution: denser phone panels add fill cost, not legibility.
##
## See also: /docs/concepts/ux.md
## See also: /docs/architecture/PERFORMANCE.md

const BASE_SIZE := Vector2(1280.0, 720.0)
const MAX_FACTOR := 4.0
const MAX_3D_PIXEL_RATIO := 2.0
const MIN_3D_SCALE := 0.5


static func factor_for(window_pixels: Vector2i, pixel_ratio: float) -> float:
	if window_pixels.x <= 0 or window_pixels.y <= 0:
		return 1.0
	var stretch := minf(float(window_pixels.x) / BASE_SIZE.x, float(window_pixels.y) / BASE_SIZE.y)
	return clampf(maxf(pixel_ratio, 1.0) / stretch, 1.0, MAX_FACTOR)


static func scale_3d_for(pixel_ratio: float) -> float:
	return clampf(MAX_3D_PIXEL_RATIO / maxf(pixel_ratio, 1.0), MIN_3D_SCALE, 1.0)


static func apply(window: Window) -> void:
	var ratio := DisplayServer.screen_get_scale()
	window.content_scale_factor = factor_for(window.size, ratio)
	window.scaling_3d_scale = scale_3d_for(ratio)
