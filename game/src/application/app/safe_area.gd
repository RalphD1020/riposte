class_name SafeArea
extends RefCounted

## Safe-area insets (notch, home indicator, rounded corners) in viewport
## units, as Vector4(left, top, right, bottom) (UX §38). On Web the export's
## head include publishes CSS env(safe-area-inset-*) as JSON; elsewhere the
## display server reports the safe rectangle. Unknown means zero.
##
## See also: /docs/concepts/ux.md

## The browser-side half of this contract is JavaScript in
## `export_presets.cfg`'s head include, which no compiler checks against this
## file. A renamed key there would not error — it would silently report zero
## inset and put the HUD under a notch, so `APP-SHELL` asserts the preset
## publishes exactly these names.
const WEB_PROPERTY := "window.riposteSafeAreaJson"
const WEB_GLOBAL := WEB_PROPERTY + " || ''"
const KEY_LEFT := "left"
const KEY_TOP := "top"
const KEY_RIGHT := "right"
const KEY_BOTTOM := "bottom"
const KEY_WIDTH := "width"
const KEY_HEIGHT := "height"
const KEYS: PackedStringArray = [KEY_LEFT, KEY_TOP, KEY_RIGHT, KEY_BOTTOM, KEY_WIDTH, KEY_HEIGHT]


static func insets(viewport_size: Vector2) -> Vector4:
	if OS.has_feature(Platform.FEATURE_WEB):
		return from_web_json(str(JavaScriptBridge.eval(WEB_GLOBAL, true)), viewport_size)
	return from_display(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(), viewport_size)


## CSS-pixel insets scaled into the stretched viewport.
static func from_web_json(text: String, viewport_size: Vector2) -> Vector4:
	var json := JSON.new()
	if text == "" or json.parse(text) != OK or not (json.data is Dictionary):
		return Vector4.ZERO
	var data := json.data as Dictionary
	var css_width := float(data.get(KEY_WIDTH, 0.0))
	if css_width <= 0.0:
		return Vector4.ZERO
	var scale := viewport_size.x / css_width
	return Vector4(
		float(data.get(KEY_LEFT, 0.0)),
		float(data.get(KEY_TOP, 0.0)),
		float(data.get(KEY_RIGHT, 0.0)),
		float(data.get(KEY_BOTTOM, 0.0))
	) * scale


## Window-pixel safe rectangle scaled into the stretched viewport.
static func from_display(safe: Rect2i, window: Vector2i, viewport_size: Vector2) -> Vector4:
	if window.x <= 0 or window.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var scale := viewport_size.x / float(window.x)
	var left := maxf(float(safe.position.x), 0.0)
	var top := maxf(float(safe.position.y), 0.0)
	var right := maxf(float(window.x - safe.end.x), 0.0)
	var bottom := maxf(float(window.y - safe.end.y), 0.0)
	return Vector4(left, top, right, bottom) * scale
