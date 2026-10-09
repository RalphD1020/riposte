class_name RiposteApp
extends Node

## Composition root (PLAN Phase 10.1). Owns player settings, telemetry, the
## presentation kit catalog, the duel camera, and the one ScreenRouter.
## Screens never construct each other; they ask the app to move. Every match
## and rematch composes a fresh MatchSession (never reset), and leaving a
## match disposes its presenter before the next screen builds. Screen swaps
## are deferred so a button is never freed inside its own signal.
##
## See also: /docs/concepts/ux.md
## See also: /docs/concepts/simulation.md

var settings: PlayerSettings = PlayerSettings.new()
var telemetry: TelemetrySink = TelemetrySink.new()
var kit_catalog: PresentationKitCatalog
var ui_feedback: UiFeedback
var router: ScreenRouter
var camera_rig: DuelCameraRig
var presentation_mount: Node3D
var match_config: MatchConfig
var last_session: MatchSession
## Where settings persist; tests point this at a scratch file.
var settings_path: String = PlayerSettings.PATH
## Non-zero pins match seeds (tests); zero draws them from entropy.
var seed_override: int = 0
var _ui_root: Control
var _seeds: RandomNumberGenerator = RandomNumberGenerator.new()
## A set is one Quick Play session: its first match is introduced, its
## rematches and rounds never are.
var _set_intro_due: bool = false


func attach(mount: Node3D, rig: DuelCameraRig, ui_root: Control) -> void:
	presentation_mount = mount
	camera_rig = rig
	_ui_root = ui_root


func _ready() -> void:
	if presentation_mount == null or camera_rig == null or _ui_root == null:
		push_error("RiposteApp: attach() the world mount, camera rig, and UI root before adding it to the tree")
		return
	if seed_override != 0:
		_seeds.seed = seed_override
	else:
		_seeds.randomize()
	settings.load_from(settings_path)
	settings.apply_audio()
	_apply_display_mode(false)
	kit_catalog = RiposteKits.build_catalog(OS.is_debug_build())
	ui_feedback = UiFeedback.new()
	ui_feedback.kit = RiposteKits.ui_theme()
	ui_feedback.reduced_motion = settings.reduced_motion
	add_child(ui_feedback)
	UiKit.feedback = ui_feedback
	camera_rig.configure(RiposteKits.camera_profile())
	_ui_root.theme = RiposteTheme.build()
	_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	router = ScreenRouter.new()
	router.bind(self)
	_ui_root.add_child(router)
	var window := get_window()
	window.size_changed.connect(_on_window_resized)
	UiScale.apply(window)
	telemetry.record_product(ProductEvents.GAME_LOADED)
	router.show_screen(AppScreen.Id.MAIN_MENU)


func go_to(screen: AppScreen.Id) -> void:
	router.show_screen.call_deferred(screen)


func current_screen() -> Control:
	return router.current()


func start_quick_play() -> void:
	telemetry.record_product(ProductEvents.QUICK_PLAY_CLICKED, {ProductEvents.PROP_DIFFICULTY: int(settings.difficulty)})
	_set_intro_due = true
	_start(MatchConfig.quick_play(settings.difficulty, _seeds.randi()))


## True exactly once per set; asking clears it.
func consume_set_intro() -> bool:
	var due := _set_intro_due
	_set_intro_due = false
	return due


func start_training() -> void:
	telemetry.record_product(ProductEvents.TUTORIAL_STARTED)
	_start(MatchConfig.training(_seeds.randi()))


func rematch() -> void:
	telemetry.record_product(ProductEvents.REMATCH_CLICKED)
	_set_intro_due = false
	if match_config == null:
		start_quick_play()
		return
	_start(match_config.rematch(_seeds.randi()))


func finish_match(session: MatchSession) -> void:
	last_session = session
	var summary := session.summary(session.config.human_slot)
	telemetry.record_product(ProductEvents.MATCH_FINISHED, {ProductEvents.PROP_OUTCOME: String(summary.outcome), ProductEvents.PROP_ROUNDS: summary.rounds})
	go_to(AppScreen.Id.RESULTS)


func quit_match() -> void:
	telemetry.record_product(ProductEvents.MATCH_EXITED)
	go_to(AppScreen.Id.MAIN_MENU)


func open_settings() -> void:
	telemetry.record_product(ProductEvents.SETTINGS_OPENED)
	go_to(AppScreen.Id.SETTINGS)


func open_community(label: String, url: String) -> void:
	telemetry.record_product(ProductEvents.COMMUNITY_CLICKED, {ProductEvents.PROP_DESTINATION: label})
	if CommunityLinks.is_configured(url):
		OS.shell_open(url)


func set_difficulty(index: int) -> void:
	settings.difficulty = clampi(index, 0, MatchConfig.Difficulty.HARD) as MatchConfig.Difficulty
	save_settings()
	telemetry.record_product(ProductEvents.DIFFICULTY_CHANGED, {ProductEvents.PROP_DIFFICULTY: int(settings.difficulty)})


func set_fullscreen(on: bool) -> void:
	settings.fullscreen = on
	save_settings()
	_apply_display_mode(true)
	if on:
		telemetry.record_product(ProductEvents.FULLSCREEN_ENTERED)


## Persist and apply. A failed save keeps the values for this visit.
func save_settings() -> void:
	settings.save_to(settings_path)
	settings.apply_audio()


func presentation_options() -> PresentationOptions:
	var options := PresentationOptions.new()
	options.reduced_motion = settings.reduced_motion
	options.reduced_flash = settings.reduced_flash
	options.screen_shake = settings.screen_shake
	options.show_charge_indicator = settings.show_charge_indicator
	options.high_contrast_weapons = settings.high_contrast_weapons
	options.trail_strength = settings.trail_value()
	options.sweet_spot_cue = settings.sweet_spot_value()
	options.haptics = settings.haptics
	options.touch_layout = touch_layout()
	options.captions = settings.captions
	options.particle_intensity = settings.particle_intensity
	return options


## Cosmetic choice per slot: the local player wears their chosen skin, the
## opponent the base look. Never part of MatchConfig, so never part of rules.
func fighter_skins() -> Array[StringName]:
	return _skins_for(StringName(settings.fighter_skin))


func weapon_skins() -> Array[StringName]:
	return _skins_for(StringName(settings.weapon_skin))


func _skins_for(choice: StringName) -> Array[StringName]:
	var skins: Array[StringName] = [&"", &""]
	if match_config != null:
		skins[match_config.human_slot] = choice
	return skins


func touch_layout() -> bool:
	return DisplayServer.is_touchscreen_available()


func safe_insets() -> Vector4:
	return SafeArea.insets(get_viewport().get_visible_rect().size)


func _start(config: MatchConfig) -> void:
	match_config = config
	last_session = null
	go_to(AppScreen.Id.MATCH)


func _on_window_resized() -> void:
	UiScale.apply(get_window())


## Browsers only grant fullscreen inside a user gesture, so on Web the saved
## preference applies when toggled, never at boot.
func _apply_display_mode(from_gesture: bool) -> void:
	if Platform.is_headless() or (Platform.is_web() and not from_gesture):
		return
	var mode := DisplayServer.window_get_mode()
	var is_full := mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	if settings.fullscreen and not is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif not settings.fullscreen and is_full:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
