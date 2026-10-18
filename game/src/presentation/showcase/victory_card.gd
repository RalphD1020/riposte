class_name VictoryCard
extends Control

## The winner's composition over the victory showcase: the fighter's name and
## title on a banner plate, the final cut's streak turned into a gold divider,
## the announcer's caption, and a sheet the results screen fills with the score
## and its actions once the cinematic lets go (PRES-VICTORY-001).
##
## Every label sits on a plate that is a proven TEXT_PAIRS combination; the
## gold is ornament only (UX-001). Motion is driven by `advance(delta)` from
## the owning screen, so it is exact in tests and has no tween to outlive it.
## Reduced Motion keeps the text and the final divider and drops the sweep.
##
## See also: /docs/concepts/presentation.md

## The divider the streak settles into, as fractions of the card's size.
const DIVIDER_FROM := Vector2(0.56, 0.04)
const DIVIDER_TO := Vector2(0.84, 0.62)
const STREAK_WIDTH := 10.0
const DIVIDER_WIDTH := 4.0
## Seconds for the streak to become the divider.
const SETTLE_SECONDS := 0.65

var reduced_motion: bool = false
var _streak: Line2D
var _streak_from := Vector2.ZERO
var _streak_to := Vector2.ZERO
var _streak_age: float = -1.0
var _banner: PanelContainer
var _mark: TextureRect
var _name: Label
var _title: Label
var _caption_plate: PanelContainer
var _caption: Label
var _caption_left: float = 0.0
var _sheet: PanelContainer
var _results: VBoxContainer
var _insets := Vector4.ZERO


static func create() -> VictoryCard:
	var card := VictoryCard.new()
	card.name = "VictoryCard"
	card._build()
	return card


func _build() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_streak = Line2D.new()
	_streak.name = "Streak"
	_streak.default_color = RiposteTheme.GOLD_ACCENT
	_streak.width = STREAK_WIDTH
	_streak.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_streak.end_cap_mode = Line2D.LINE_CAP_ROUND
	_streak.visible = false
	add_child(_streak)
	_banner = PanelContainer.new()
	_banner.name = "NamePlate"
	_banner.theme_type_variation = &"BannerPlate"
	_banner.mouse_filter = MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.mouse_filter = MOUSE_FILTER_IGNORE
	_banner.add_child(stack)
	_mark = TextureRect.new()
	_mark.name = "Mark"
	_mark.custom_minimum_size = Vector2(64.0, 64.0)
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.mouse_filter = MOUSE_FILTER_IGNORE
	_mark.visible = false
	stack.add_child(_mark)
	_name = Label.new()
	_name.theme_type_variation = &"BannerLabel"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_name)
	_title = Label.new()
	_title.theme_type_variation = &"HudAccentLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(_title)
	_caption_plate = PanelContainer.new()
	_caption_plate.name = "CaptionPlate"
	_caption_plate.theme_type_variation = &"CaptionPlate"
	_caption_plate.mouse_filter = MOUSE_FILTER_IGNORE
	_caption_plate.visible = false
	add_child(_caption_plate)
	_caption = Label.new()
	_caption.theme_type_variation = &"AnnouncerCaption"
	_caption.accessibility_live = AccessibilityServer.LIVE_POLITE
	_caption_plate.add_child(_caption)
	_sheet = PanelContainer.new()
	_sheet.name = "ResultsSheet"
	_sheet.theme_type_variation = &"Sheet"
	_sheet.mouse_filter = MOUSE_FILTER_STOP
	_sheet.visible = false
	add_child(_sheet)
	var margin := MarginContainer.new()
	margin.theme_type_variation = &"SheetMargin"
	_sheet.add_child(margin)
	_results = VBoxContainer.new()
	_results.custom_minimum_size = Vector2(RiposteTheme.SHEET_WIDTH, 0.0)
	margin.add_child(_results)
	resized.connect(_layout)


## Where the results screen puts the score and its actions.
func results_host() -> VBoxContainer:
	return _results


func layout_insets(insets: Vector4) -> void:
	_insets = insets
	_layout()


## The fighter's name and title arrive.
## The winner's mark, from the kit. Absent until a kit has one.
func set_mark(texture: Texture2D) -> void:
	_mark.texture = texture
	_mark.visible = texture != null and _banner.visible


func has_mark() -> bool:
	return _mark.visible and _mark.texture != null


func show_card(display_name: String, title: String) -> void:
	_name.text = display_name
	_title.text = title
	_banner.visible = display_name != ""
	_mark.visible = _mark.texture != null and _banner.visible
	_layout()


func card_text() -> String:
	return _name.text if _banner.visible else ""


func title_text() -> String:
	return _title.text if _banner.visible else ""


## The final cut's streak, in screen space, at the instant it lands. From here
## it settles into the divider beside the name.
func set_streak(from: Vector2, to: Vector2) -> void:
	_streak_from = from
	_streak_to = to
	_streak_age = SETTLE_SECONDS if reduced_motion else 0.0
	_streak.visible = true
	_draw_streak()


func has_streak() -> bool:
	return _streak.visible


func show_caption(text: String, seconds: float) -> void:
	_caption.text = text
	_caption_plate.visible = text != ""
	_caption_left = seconds
	_layout()


func caption_text() -> String:
	return _caption.text if _caption_plate.visible else ""


## The cinematic let go: the results sheet appears.
func reveal_results() -> void:
	_sheet.visible = true
	_layout()


func are_results_revealed() -> bool:
	return _sheet.visible


func advance(delta: float) -> void:
	if _streak_age >= 0.0 and _streak_age < SETTLE_SECONDS:
		_streak_age = minf(_streak_age + maxf(delta, 0.0), SETTLE_SECONDS)
		_draw_streak()
	if _caption_left > 0.0:
		_caption_left -= delta
		if _caption_left <= 0.0:
			_caption_plate.visible = false


func _draw_streak() -> void:
	var t := smoothstep(0.0, 1.0, _streak_age / SETTLE_SECONDS)
	var a := _streak_from.lerp(DIVIDER_FROM * size, t)
	var b := _streak_to.lerp(DIVIDER_TO * size, t)
	_streak.points = PackedVector2Array([a, b])
	_streak.width = lerpf(STREAK_WIDTH, DIVIDER_WIDTH, t)


func _layout() -> void:
	var edge := RiposteTheme.MARGIN
	_banner.reset_size()
	_banner.position = Vector2(size.x - _insets.z - edge - _banner.size.x, _insets.y + edge)
	## The announcer is captioned under the name it reads, clear of the sheet.
	_caption_plate.reset_size()
	_caption_plate.position = Vector2(size.x - _insets.z - edge - _caption_plate.size.x, _banner.position.y + _banner.size.y + RiposteTheme.STACK_GAP)
	_sheet.reset_size()
	_sheet.position = Vector2(_insets.x + edge, size.y - _insets.w - edge - _sheet.size.y)
	if _streak.visible:
		_draw_streak()
