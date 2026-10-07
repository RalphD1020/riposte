class_name Platform
extends RefCounted

## One home for the strings that name a platform. Godot answers these
## questions with free-form text, so a typo is not an error — it is a silently
## false branch, and these branches decide whether the game reads safe-area
## insets and whether it may touch the window mode at all.
##
## Deliberately thin. Touch layout is `DisplayServer.is_touchscreen_available`,
## not a platform guess, and `OS.has_feature("mobile")` is false in a browser
## and lint-rejected (`game/scripts/lint.mjs`) — if a web-mobile branch ever
## becomes necessary, `web_android` / `web_ios` belong here beside these.
##
## See also: /docs/reference/godot.md

const FEATURE_WEB := "web"
## `DisplayServer.get_name()` under `--headless`; the test harness runs here.
const DISPLAY_HEADLESS := "headless"


static func is_web() -> bool:
	return OS.has_feature(FEATURE_WEB)


## No window to resize, no display mode to set, no fullscreen to grant.
static func is_headless() -> bool:
	return DisplayServer.get_name() == DISPLAY_HEADLESS
