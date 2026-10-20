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
var monitors: SimulationMonitors = SimulationMonitors.new()
var kit_catalog: PresentationKitCatalog
var ui_feedback: UiFeedback
var router: ScreenRouter
var camera_rig: DuelCameraRig
var presentation_mount: Node3D
var match_config: MatchConfig
var last_session: MatchSession
## Where settings persist; tests point this at a scratch file.
var settings_path: String = PlayerSettings.PATH
## The one music player. Menus and the match select its stream. The victory
## sting does not: the showcase plays that one-shot itself. Results stops this
## loop. Rematch starts the arena theme again.
const MENU_LOOP := "res://assets/presentation/audio/music/menu_theme.mp3"
const LOOP_VOLUME_DB := -8.0
## Applied to the outgoing playback before stop. Godot fades a stopped
## stream for one mix buffer; muting first keeps that buffer from being
## the previous theme.
const LOOP_CUT_DB := -80.0
## Exact diagnostic when MATCH has no arena stream. The test runner allows
## this one `ERROR:` line; other engine errors still fail the gate.
const FAULT_MATCH_MUSIC_MISSING := "RiposteApp: match music is missing"
var _loop: AudioStreamPlayer
var _menu_music: AudioStream
## Arena theme published by MatchScreen._ready before the router reports MATCH.
## Null means the match has no valid stream; the selector stops the loop.
var _match_music: AudioStream
## The stream the one player should be on. An MP3 is not monophonic, so
## `play()` stacks a voice, and `stop()` only fades the old one. The new
## voice starts on the next frame, after that fade has left the server.
var _pending_music: AudioStream
## Level applied when the pending voice actually starts. Themes use
## `LOOP_VOLUME_DB`.
var _pending_volume_db: float = LOOP_VOLUME_DB
var _music_dirty: bool = false
## How many times `play()` ran on the loop. Same stream already playing does
## not increment. Playback position is not this contract.
var _loop_starts: int = 0
## Last MATCH-music fault, or empty. Tests assert this; `push_error` still
## prints it for the engine log.
var last_music_fault: String = ""
## Non-zero pins match seeds (tests); zero draws them from entropy.
var seed_override: int = 0
var _ui_root: Control
var _seeds: RandomNumberGenerator = RandomNumberGenerator.new()
## The set in progress: one match. Quick Play and every Rematch open a new one,
## so each is introduced once and its winner showcased once (PRES-INTRO-001,
## PRES-VICTORY-001); rounds inside it never are.
var current_set: MatchSet
var _next_set_id: int = 0
## Test seam, like `seed_override`: when set, composes the session instead of
## `MatchComposer.compose(config, human, telemetry)` — so a scenario can stand a
## scripted opponent opposite the real human pipeline. Production never sets it.
var compose_session: Callable


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
	settings.apply_bindings()
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
	_loop = AudioStreamPlayer.new()
	_loop.name = "MusicLoop"
	_loop.bus = AudioBuses.MUSIC
	_loop.volume_db = LOOP_VOLUME_DB
	## A long loop is a stream. The sample playback path is for one-shots;
	## a looping sample can keep mixing after this player's stream has changed.
	_loop.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	_loop.max_polyphony = 1
	add_child(_loop)
	set_process(false)
	_menu_music = load(MENU_LOOP) as AudioStream
	router.screen_changed.connect(_on_screen_changed)
	var window := get_window()
	window.size_changed.connect(_on_window_resized)
	UiScale.apply(window)
	telemetry.record_product(ProductEvents.GAME_LOADED)
	monitors.install()
	router.show_screen(AppScreen.Id.MAIN_MENU)


func _exit_tree() -> void:
	monitors.uninstall()


## The match screen publishes its arena theme here, before `screen_changed`.
## A missing stream is a fault: the MATCH selector stops the loop rather than
## keeping the menu theme.
func publish_match_music(stream: AudioStream) -> void:
	_match_music = stream


## Select the one music voice. The same stream, already playing, is left
## alone, so opening Settings does not restart the menu and a new round does
## not restart the arena theme. A different stream, or a stop, mutes this
## player now and applies the change next frame, so two themes are never both
## in the mix. A null stream stops it.
func play_loop(stream: AudioStream, volume_db: float = LOOP_VOLUME_DB) -> void:
	if _loop == null:
		return
	if _music_dirty and stream == _pending_music:
		return
	if not _music_dirty and stream != null and _loop.stream == stream and _loop.playing:
		return
	_pending_music = stream
	_pending_volume_db = volume_db
	_music_dirty = true
	_loop.volume_db = LOOP_CUT_DB
	_loop.stop()
	_loop.stream = null
	set_process(true)
	_music_dirty = true
	_loop.volume_db = LOOP_CUT_DB
	_loop.stop()
	_loop.stream = null
	set_process(true)


func _process(_delta: float) -> void:
	if not _music_dirty or _loop == null:
		set_process(false)
		return
	_music_dirty = false
	var stream := _pending_music
	_loop.volume_db = _pending_volume_db
	set_process(false)
	if stream == null:
		return
	if _loop.playing:
		_loop.stop()
	_loop.stream = stream
	_loop.play()
	_loop_starts += 1


func is_loop_playing() -> bool:
	return _loop != null and _loop.playing


func loop_stream() -> AudioStream:
	if _music_dirty:
		return _pending_music
	return _loop.stream if _loop != null else null


## Diagnostic only. Godot's playback position can lag the mix; tests must
## not treat it as proof the loop was not restarted. Use `loop_start_count`.
func loop_playback_position() -> float:
	if _loop == null or not _loop.playing:
		return 0.0
	return _loop.get_playback_position()


func loop_start_count() -> int:
	return _loop_starts


func loop_volume_db() -> float:
	return 0.0 if _loop == null else _loop.volume_db


## Instance id of the one MusicLoop player. Tests use this to prove the
## playing Music loop is this node, not a second source.
func loop_player_id() -> int:
	return 0 if _loop == null else _loop.get_instance_id()


## MATCH plays the published arena theme through every round. RESULTS stops
## it: the match is over, and the victory sting is the showcase's own player.
## Rematch is a new MATCH, so the arena theme starts again. A menu screen
## plays the menu theme. A missing arena stream on MATCH stops the loop
## rather than keeping the menu.
func select_screen_music(screen: AppScreen.Id) -> void:
	last_music_fault = ""
	if screen == AppScreen.Id.RESULTS:
		play_loop(null)
		return
	if screen == AppScreen.Id.MATCH:
		if _match_music == null:
			last_music_fault = FAULT_MATCH_MUSIC_MISSING
			push_error(FAULT_MATCH_MUSIC_MISSING)
			play_loop(null)
			return
		play_loop(_match_music)
		return
	play_loop(_menu_music)


func _on_screen_changed(screen: AppScreen.Id) -> void:
	select_screen_music(screen)


func go_to(screen: AppScreen.Id) -> void:
	router.show_screen.call_deferred(screen)


func current_screen() -> Control:
	return router.current()


var crowd_seed: int = 1


func start_quick_play() -> void:
	telemetry.record_product(ProductEvents.QUICK_PLAY_CLICKED, {ProductEvents.PROP_DIFFICULTY: int(settings.difficulty)})
	crowd_seed = absi(_seeds.randi()) | 1
	_start(MatchConfig.quick_play(settings.difficulty, _seeds.randi()))


## True exactly once per set; asking clears it.
func claim_set_intro() -> bool:
	return current_set != null and current_set.claim_intro()


## True exactly once per set whose winner is showcased; asking clears it.
func claim_set_victory() -> bool:
	return current_set != null and current_set.claim_victory()


func start_training() -> void:
	telemetry.record_product(ProductEvents.TUTORIAL_STARTED)
	crowd_seed = absi(_seeds.randi()) | 1
	_start(MatchConfig.training(_seeds.randi()))


## A rematch is a new set: fresh session, fresh seed, introduced again.
func rematch() -> void:
	telemetry.record_product(ProductEvents.REMATCH_CLICKED)
	if match_config == null:
		start_quick_play()
		return
	_start(match_config.rematch(_seeds.randi()))


## The match's presentation kits, resolved once for the duel and again for its
## results: rules decide identity, settings decide the local player's skin.
func resolve_kits(config: MatchConfig) -> DuelKits:
	var kits := DuelKits.resolve(kit_catalog, config.rules, fighter_skins(), weapon_skins())
	if kits.is_complete():
		kits.match_loadout = RiposteKits.match_loadout(kits.arena)
	return kits


## The session for `config`, through the test seam when one is installed.
func compose(config: MatchConfig, human: HumanController) -> MatchSession:
	var session: MatchSession
	if compose_session.is_valid():
		session = compose_session.call(config, human, telemetry) as MatchSession
	else:
		session = MatchComposer.compose(config, human, telemetry)
	monitors.session = session
	return session


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
	settings.apply_bindings()


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
	options.sound_captions = settings.sound_captions
	options.contact_highlight = settings.contact_highlight
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
	_next_set_id += 1
	## Training is practice, not a set: no introduction, no showcase.
	var shown := config.mode == MatchConfig.Mode.QUICK_PLAY_CPU
	current_set = MatchSet.open(_next_set_id, shown, shown)
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
