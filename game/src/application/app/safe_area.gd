class_name SafeArea
extends RefCounted

## Safe-area insets (notch, home indicator, rounded corners) in viewport
## units, as Vector4(left, top, right, bottom) (UX §38). On Web the export's
## head include publishes CSS env(safe-area-inset-*) as JSON; elsewhere the
## display server reports the safe rectangle. Unknown means zero.
##
## See also: /docs/concepts/ux.md

const WEB_GLOBAL := "window.riposteSafeAreaJson || ''"


static func insets(viewport_size: Vector2) -> Vector4:
	if OS.has_feature("web"):
		return from_web_json(str(JavaScriptBridge.eval(WEB_GLOBAL, true)), viewport_size)
	return from_display(DisplayServer.get_display_safe_area(), DisplayServer.window_get_size(), viewport_size)


## CSS-pixel insets scaled into the stretched viewport.
static func from_web_json(text: String, viewport_size: Vector2) -> Vector4:
	var json := JSON.new()
	if text == "" or json.parse(text) != OK or not (json.data is Dictionary):
		return Vector4.ZERO
	var data := json.data as Dictionary
	var css_width := float(data.get("width", 0.0))
	if css_width <= 0.0:
		return Vector4.ZERO
	var scale := viewport_size.x / css_width
	return Vector4(
		float(data.get("left", 0.0)),
		float(data.get("top", 0.0)),
		float(data.get("right", 0.0)),
		float(data.get("bottom", 0.0))
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
