class_name HudIcons
extends RefCounted

## Tiny generated icons, so no state depends on a glyph the shipped font may
## lack (the fallback font has no ✓ ● ○; on Web there is no system fallback).
## Replace with authored textures here, in one place.
##
## See also: /docs/concepts/presentation.md

const PAUSE_SIZE := 20
const PAUSE_BAR_WIDTH := 6
const PAUSE_GAP := 4
const MARKER_SIZE := 12
const SWITCH_WIDTH := 44
const SWITCH_HEIGHT := 26
const SWITCH_BORDER := 2.0
const KNOB_SIZE := 22
const KNOB_RING := 2.5

static var _pause: ImageTexture
static var _markers: Dictionary = {}
static var _switches: Dictionary = {}
static var _knob: ImageTexture


static func pause() -> ImageTexture:
	if _pause == null:
		var image := _blank(PAUSE_SIZE)
		var left := floori(float(PAUSE_SIZE - 2 * PAUSE_BAR_WIDTH - PAUSE_GAP) / 2.0)
		image.fill_rect(Rect2i(left, 2, PAUSE_BAR_WIDTH, PAUSE_SIZE - 4), RiposteTheme.TEXT_ON_DARK)
		image.fill_rect(Rect2i(left + PAUSE_BAR_WIDTH + PAUSE_GAP, 2, PAUSE_BAR_WIDTH, PAUSE_SIZE - 4), RiposteTheme.TEXT_ON_DARK)
		_pause = ImageTexture.create_from_image(image)
	return _pause


## A filled dot marking the selected option alongside its fill (UX §50, §84).
static func marker(color: Color) -> ImageTexture:
	var key := color.to_html()
	if not _markers.has(key):
		var image := _blank(MARKER_SIZE)
		var center := (float(MARKER_SIZE) - 1.0) * 0.5
		var radius := float(MARKER_SIZE) * 0.5 - 0.5
		for y in MARKER_SIZE:
			for x in MARKER_SIZE:
				var coverage := clampf(radius - Vector2(float(x) - center, float(y) - center).length() + 0.5, 0.0, 1.0)
				if coverage > 0.0:
					image.set_pixel(x, y, Color(color, coverage))
		_markers[key] = ImageTexture.create_from_image(image)
	return _markers[key]


## Toggle switch with ≥ 3:1 parts on the light surface (UX §44): on is a
## filled steel track with the knob right; off is an outlined track with a
## steel knob left, so state reads by shape and position, not color.
static func switch(on: bool) -> ImageTexture:
	if not _switches.has(on):
		var image := Image.create_empty(SWITCH_WIDTH, SWITCH_HEIGHT, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		var radius := float(SWITCH_HEIGHT) * 0.5
		var knob_radius := radius - 5.0
		var knob_x := float(SWITCH_WIDTH) - radius if on else radius
		for y in SWITCH_HEIGHT:
			for x in SWITCH_WIDTH:
				var point := Vector2(float(x) + 0.5, float(y) + 0.5)
				var axis_x := clampf(point.x, radius, float(SWITCH_WIDTH) - radius)
				var edge := radius - point.distance_to(Vector2(axis_x, radius))
				var track := clampf(edge + 0.5, 0.0, 1.0)
				if track <= 0.0:
					continue
				var color := RiposteTheme.STEEL_900
				if not on and edge > SWITCH_BORDER:
					color = RiposteTheme.SURFACE
				var knob_coverage := clampf(knob_radius - point.distance_to(Vector2(knob_x, radius)) + 0.5, 0.0, 1.0)
				if knob_coverage > 0.0:
					color = color.lerp(RiposteTheme.SURFACE if on else RiposteTheme.STEEL_900, knob_coverage)
				image.set_pixel(x, y, Color(color, track))
		_switches[on] = ImageTexture.create_from_image(image)
	return _switches[on]


## Slider grabber: a steel disc inside a white ring, so the handle reads on
## both the light track and the steel fill (UX §44).
static func knob() -> ImageTexture:
	if _knob == null:
		var image := _blank(KNOB_SIZE)
		var center := (float(KNOB_SIZE) - 1.0) * 0.5
		var radius := float(KNOB_SIZE) * 0.5 - 0.5
		for y in KNOB_SIZE:
			for x in KNOB_SIZE:
				var distance := Vector2(float(x) - center, float(y) - center).length()
				var coverage := clampf(radius - distance + 0.5, 0.0, 1.0)
				if coverage > 0.0:
					var color := RiposteTheme.SURFACE if distance > radius - KNOB_RING else RiposteTheme.STEEL_900
					image.set_pixel(x, y, Color(color, coverage))
		_knob = ImageTexture.create_from_image(image)
	return _knob


static func _blank(size: int) -> Image:
	var image := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	return image
