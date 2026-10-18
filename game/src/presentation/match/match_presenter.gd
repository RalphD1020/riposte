class_name MatchPresenter
extends Node3D

## The transient 3D root and the one presentation coordinator for a match.
##
## Per simulation tick: `push(snapshot, events)` stores the new snapshot and
## hands the events to `CombatFeedbackDirector`, then carries out the
## `FeedbackFrame` it returns (sparks, rings, sounds, hitstop, impulses,
## haptics). Per frame: `render(alpha, delta)` interpolates between the last
## two snapshots with the tick driver's alpha and poses the passive proxies.
## It never steps, reads, or mutates the simulation; hitstop and slow motion
## are requests to the clock owner. Generic code here never names a content
## identity.
##
## Implements: /spec/invariants.md#pres-001, /spec/invariants.md#pres-002
## See also: /docs/concepts/presentation.md

signal hitstop_requested(seconds: float)
signal slow_motion_requested(time_scale: float, seconds: float)
## A combat sound as text, when sound captions are on (`SoundCaptions`).
signal sound_caption_requested(text: String, seconds: float)

## Speed of a grind spark thrown from a scraping contact (m/s).
const GRIND_SPEED := 0.9
## Crowd bed trim. The Crowd bus fader is the player's mix; this is the
## presentation ride, written only when the change passes hysteresis.
const CROWD_BED_AMBIENT_DB := -18.0
const CROWD_BED_MOMENTUM_DB := -10.0
const CROWD_BED_SLEW_DB := 24.0
const CROWD_BED_HYSTERESIS_DB := 0.35

var _kits: DuelKits
var _options: PresentationOptions
var _camera: DuelCameraRig
var _haptics := Haptics.new()
var _arena: ArenaScaffold
var _fighters: Array[FighterPresentation3D] = []
var _trails: Array[SwordTrail3D] = []
var _vectors: DebugVectors3D
var _vfx: VfxDirector
var _audio: AudioDirector
var _previous: PresentationSnapshot
var _current: PresentationSnapshot
var _snap: bool = true
var _disposed: bool = false
var _last_frame: FeedbackFrame = FeedbackFrame.new()
## Killing blows → the first backend that can carry them out. Primitive today;
## a ragdoll backend goes ahead of it once the rig has a physical skeleton.
var _deaths: DeathPresentationController
## Swords waiting for the hands to let go, and the ones already tumbling.
var _drops := WeaponDropController.new()
var _dropped: Array[DroppedWeapon3D] = []
var _contact := ContactPresentation.new()
## The current tick's rendered contact height, NAN when the swords are apart.
var _contact_height: float = NAN
## Friction work not yet thrown as grind sparks (J, `ContactScrape`).
var _spark_energy: float = 0.0
## Only built when the option is on.
var _highlight: ContactHighlight3D
## The held contact whose scrape was last captioned, so one scrape is one
## caption however long it lasts; -1 when none is held.
var _captioned_scrape: int = -1
var _scrape_started: bool = false
var _crowd_intensity: float = 0.0
var _crowd_bed_trim: float = CROWD_BED_AMBIENT_DB
var _crowd_bed_written: float = INF


static func create(kits: DuelKits, options: PresentationOptions, camera: DuelCameraRig, platform_radius: float, edge_warning_inset: float, first: PresentationSnapshot) -> MatchPresenter:
	var presenter := MatchPresenter.new()
	presenter.name = "MatchPresentation"
	presenter._kits = kits
	presenter._options = options
	presenter._camera = camera
	presenter._haptics.enabled = options.haptics
	presenter._build(platform_radius, edge_warning_inset, first)
	return presenter


func _ready() -> void:
	## The arena loop belongs to RiposteApp. This director starts the bed only.
	if _kits.arena != null:
		_audio.play_crowd_bed(_kits.arena.stream_for(PresentationKit.CUE_CROWD_BED))
		_audio.set_crowd_bed_volume_db(CROWD_BED_AMBIENT_DB)
		_crowd_bed_trim = CROWD_BED_AMBIENT_DB
		_crowd_bed_written = CROWD_BED_AMBIENT_DB


func push(snapshot: PresentationSnapshot, events: Array[DuelEvent]) -> void:
	var restarted := _current != null and snapshot.phase == MatchPhase.Id.ROUND_INTRO and _current.phase != MatchPhase.Id.ROUND_INTRO
	_previous = _current if _current != null and not restarted else snapshot
	_current = snapshot
	if restarted:
		_snap = true
		for ribbon in _trails:
			ribbon.clear_trail()
		for slot in 2:
			_audio.release_tension(slot)
		_audio.release_bind(0)
		_spark_energy = 0.0
		_captioned_scrape = -1
		_deaths.reset()
		_clear_drops()
		for proxy in _fighters:
			proxy.reset_terminal()
	var style := _kits.match_loadout.vfx_style if _kits.match_loadout != null else null
	## One rendered contact height for the tick (CONTACT-PRESENTATION-001):
	## the drawn swords, the clash sparks and the grind all meet there.
	_contact_height = _contact.contact_height(snapshot, _kits.weapon.blade_height)
	_last_frame = CombatFeedbackDirector.process(snapshot, events, _kits.weapon, _options.flash_scale(), _options.particle_intensity, style, _contact_height)
	_apply(_last_frame)
	_grind(snapshot, style)
	if _highlight != null:
		var none: Array[PresentationContact] = []
		_highlight.show_contacts(none if is_nan(_contact_height) else snapshot.contacts, _contact_height)
	_caption_sounds()


## One caption per tick: the most significant sound the frame played, else a
## scrape that has just become audible.
func _caption_sounds() -> void:
	var scrape := _scrape_started
	_scrape_started = false
	if not _options.sound_captions:
		return
	var text := SoundCaptions.pick(_last_frame.audio_requests)
	if text == "" and scrape:
		text = HudCopy.SOUND_SCRAPE
	if text != "":
		sound_caption_requested.emit(text, SoundCaptions.HOLD_SECONDS)


## One display frame. `real_delta` is wall-clock time (camera, VFX, trails);
## `scaled_delta` is presentation-scaled time — real time with hitstop as zero
## and slow motion at its scale — which drives the fighters' clips and every
## terminal timer (PRES-TIME-001). Omitted, it equals real time.
func render(alpha: float, real_delta: float, scaled_delta: float = -1.0) -> void:
	if _current == null or _disposed:
		return
	var scaled := real_delta if scaled_delta < 0.0 else scaled_delta
	var weight := clampf(alpha, 0.0, 1.0)
	var first := _pose(0, weight, real_delta, scaled, _contact_height)
	var second := _pose(1, weight, real_delta, scaled, _contact_height)
	_vectors.update(_current)
	_vfx.advance(real_delta)
	for drop in _drops.advance(scaled):
		_launch_drop(drop)
	if _camera != null:
		_camera.frame(first, second, real_delta, _options, _snap)
	_snap = false
	_ride_crowd_bed(real_delta)


func fighter_proxy(slot: int) -> FighterPresentation3D:
	return _fighters[slot]


## The once-per-set introduction, built over this presenter's world from the
## fighters' recorded takes. The screen decides whether a set is starting and
## records the takes; the presenter only stages them.
func create_intro(gameplay_camera: Camera3D, takes: Array[IntroTake] = []) -> SetIntroDirector:
	var proxies: Array[Node3D] = []
	for proxy in _fighters:
		proxies.append(proxy)
	for ribbon in _trails:
		proxies.append(ribbon)
	var intro := SetIntroDirector.create(_kits, _current, _audio, proxies, gameplay_camera, takes)
	add_child(intro)
	return intro


func trail(slot: int) -> SwordTrail3D:
	return _trails[slot]


## The world-space debug vectors, so the screen that owns the debug toggle can
## show them beside the text overlay.
func debug_vectors() -> DebugVectors3D:
	return _vectors


func vfx() -> VfxDirector:
	return _vfx


func play_crowd(cue: StringName, winner: int, intensity: float = 0.0) -> void:
	_crowd_intensity = clampf(intensity, 0.0, 1.0)
	if cue == &"" or cue == CrowdDirector.CUE_MURMUR or _kits == null or _kits.arena == null:
		return
	if cue == CrowdDirector.CUE_VICTORY and MatchPhase.is_combatant(winner):
		var chant := _kits.combatant(winner).fighter.crowd_chant
		if chant != null:
			_audio.play_crowd_shot(chant)
			return
	var named := _crowd_cue(cue)
	if named == &"":
		return
	_audio.play_crowd_cue(_kits.arena, named)


func _crowd_cue(cue: StringName) -> StringName:
	match cue:
		CrowdDirector.CUE_CHEER:
			return PresentationKit.CUE_CROWD_CHEER
		CrowdDirector.CUE_STRONG:
			return PresentationKit.CUE_CROWD_STRONG
		CrowdDirector.CUE_SETPOINT:
			return PresentationKit.CUE_CROWD_SETPOINT
		CrowdDirector.CUE_VICTORY:
			return PresentationKit.CUE_CROWD_VICTORY
		CrowdDirector.CUE_GASP:
			return PresentationKit.CUE_CROWD_GASP
		_:
			return &""


func _ride_crowd_bed(delta: float) -> void:
	if _audio == null or not _audio.is_crowd_bed_playing():
		return
	var target := lerpf(CROWD_BED_AMBIENT_DB, CROWD_BED_MOMENTUM_DB, _crowd_intensity)
	_crowd_bed_trim = move_toward(_crowd_bed_trim, target, CROWD_BED_SLEW_DB * maxf(delta, 0.0))
	if is_inf(_crowd_bed_written) or absf(_crowd_bed_trim - _crowd_bed_written) >= CROWD_BED_HYSTERESIS_DB:
		_audio.set_crowd_bed_volume_db(_crowd_bed_trim)
		_crowd_bed_written = _crowd_bed_trim


## The arena's match horn, not a fighter's cue. A stage without one stays silent.
func play_set_horn() -> void:
	if _kits == null or _kits.arena == null:
		return
	_audio.play_sting(_kits.arena.stream_for(PresentationKit.CUE_MATCH_HORN))


func audio() -> AudioDirector:
	return _audio


func haptics() -> Haptics:
	return _haptics


func current_snapshot() -> PresentationSnapshot:
	return _current


## The contact-point highlight, null when the option is off.
func contact_highlight() -> ContactHighlight3D:
	return _highlight


## The current tick's rendered contact height (m), NAN when apart.
func contact_height() -> float:
	return _contact_height


## The requests the last pushed tick produced, for tests and debug.
func last_frame() -> FeedbackFrame:
	return _last_frame


func duel_kits() -> DuelKits:
	return _kits


## Remove from the tree and free. Idempotent; safe during teardown.
func detach_and_dispose() -> void:
	if _disposed:
		return
	_disposed = true
	_vfx.clear_all()
	_audio.stop_all()
	var parent := get_parent()
	if parent != null:
		parent.remove_child(self)
	queue_free()


func _build(platform_radius: float, edge_warning_inset: float, first: PresentationSnapshot) -> void:
	_arena = ArenaScaffold.create(_kits.arena, platform_radius, edge_warning_inset, first.spawn_offset)
	add_child(_arena)
	for slot in 2:
		var row := first.fighter(slot)
		var proxy := FighterPresentation3D.create(slot, row.side, _kits.combatant(slot), row.push_radius, row.combatant_spec)
		proxy.set_charge_indicator(_options.show_charge_indicator)
		proxy.set_high_contrast(_options.high_contrast_weapons)
		add_child(proxy)
		_fighters.append(proxy)
		var capacity := _kits.weapon.trail_samples * (2 if _options.high_contrast_weapons else 1)
		var ribbon := SwordTrail3D.create(proxy.blade_color(), capacity)
		ribbon.set_strength(_options.trail_strength, _options.sweet_spot_cue)
		add_child(ribbon)
		_trails.append(ribbon)
	_vectors = DebugVectors3D.create(_kits.weapon.blade_height)
	add_child(_vectors)
	if _options.contact_highlight:
		_highlight = ContactHighlight3D.create()
		add_child(_highlight)
	_vfx = VfxDirector.new()
	add_child(_vfx)
	_audio = AudioDirector.new()
	add_child(_audio)
	var backends: Array[DeathPresentationBackend] = [PrimitiveDeathBackend.new(_fighters)]
	_deaths = DeathPresentationController.new(backends)
	_previous = first
	_current = first


## Interpolate one fighter between the last two snapshots, pose its proxy
## and trail, and return where it stands in the world. The blade angle is
## the chord between those snapshots. A reversal inside the tick can draw a
## crossing the two end poses do not contain. That is presentation. It does
## not write the weapon, and engine physics interpolation is not also applied
## to these proxies.
func _pose(slot: int, weight: float, real_delta: float, scaled_delta: float, height: float = NAN) -> Vector3:
	var from := _previous.fighter(slot)
	var to := _current.fighter(slot)
	var world := ArenaTransform.to_world(lerpf(from.x, to.x, weight), lerpf(from.y, to.y, weight))
	var proxy := _fighters[slot]
	var time_scale := scaled_delta / real_delta if real_delta > 0.0 else 1.0
	var lift := lift_inputs(from, to, weight)
	proxy.apply_pose(world, lerp_angle(from.facing, to.facing, weight), lerpf(from.weapon_angle, to.weapon_angle, weight), to, scaled_delta, time_scale, height, lift.x, lift.y)
	var blade := proxy.trail_points()
	_trails[slot].add_sample(blade[0], blade[1], to.swing_potential, to.blade_speed, _kits.weapon.trail_min_speed)
	_trails[slot].advance(real_delta)
	_tension(slot, to, world)
	return world


## The sword lift's continuous inputs between two snapshots, (swing progress,
## charge), interpolated like the blade angle they ride with: drawn between
## ticks — a faster display, slow motion — the lift moves with the sword
## instead of stepping once a tick. Across a phase change the current row's
## own values are used and the proxy's carry blend owns the continuity. Pure.
static func lift_inputs(from: PresentationFighter, to: PresentationFighter, weight: float) -> Vector2:
	if from.phase != to.phase:
		return Vector2(to.swing_progress, to.charge)
	return Vector2(lerpf(from.swing_progress, to.swing_progress, weight), lerpf(from.charge, to.charge, weight))


## The charge is shown by the body — the sword gathered up toward the striking
## shoulder, point rising with the wind-back actually earned (PRES-CARRIAGE-001)
## — and audio only tightens behind it, plateauing when there is no more to
## earn. No charge glow (UX §19).
func _tension(slot: int, row: PresentationFighter, world: Vector3) -> void:
	if row.phase == CombatPhase.Id.CHARGING and row.is_alive():
		_audio.hold_tension(slot, _kits.weapon, world, row.charge)
	else:
		_audio.release_tension(slot)


## Swords held against each other scrape as hard as friction works there
## (`ContactScrape`): the held point doing the most friction work carries the
## sound at the shared rendered contact, keyed by its `contact_id` so one
## contact keeps one take; grind sparks are thrown at a rate set by the same
## work. A blade pressed still is silent and throws nothing; the scrape lets go
## the tick no point is held. Never a hitstop — a held contact is not a hit.
func _grind(snapshot: PresentationSnapshot, style: VfxStyleKit) -> void:
	var scraping := ContactScrape.dominant(snapshot.contacts)
	if scraping < 0:
		_audio.release_bind(0)
		_spark_energy = 0.0
		_captioned_scrape = -1
		return
	var row := snapshot.contacts[scraping]
	if row.contact_id != _captioned_scrape and ContactScrape.level(ContactScrape.power(row)) > 0.0:
		_captioned_scrape = row.contact_id
		_scrape_started = true
	var height := _kits.weapon.blade_height if is_nan(_contact_height) else _contact_height
	var point := ArenaTransform.to_world(row.x, row.y, height)
	_audio.hold_bind(0, _kits.weapon, point, ContactScrape.level(ContactScrape.power(row)), row.contact_id)
	_spark_energy += ContactScrape.total_power(snapshot.contacts)
	var sparks := mini(floori(_spark_energy / ContactScrape.SPARK_ENERGY), ContactScrape.SPARKS_PER_TICK)
	_spark_energy = minf(_spark_energy - float(sparks) * ContactScrape.SPARK_ENERGY, ContactScrape.SPARK_ENERGY)
	if sparks > 0 and _options.particle_intensity > 0.0:
		var color := style.grind if style != null else RiposteTheme.SPARK
		_vfx.sparks(point, Vector3.UP, color, sparks, GRIND_SPEED, _options.flash_scale())


## Grind sparks this tick would throw (for tests and debug): the friction work
## banked toward the next spark.
func grind_energy() -> float:
	return _spark_energy


func _apply(frame: FeedbackFrame) -> void:
	TerminalPresentationPolicy.filter(frame, _current)
	for request in frame.camera_requests:
		_impulse(request.intensity / 100.0, request.direction)
	for request in frame.hitstop_requests:
		hitstop_requested.emit(request.duration)
	for request in frame.slow_motion_requests:
		slow_motion_requested.emit(request.time_scale, request.seconds)
	for request in frame.audio_requests:
		_play(request)
	for request in frame.vfx_requests:
		_draw(request)
	for request in frame.fighter_requests:
		_fighter_cue(request)
	for request in frame.death_requests:
		_present_death(request)
	for request in frame.fall_requests:
		_fighters[request.slot].begin_fall(request)
	for request in frame.weapon_drop_requests:
		_drops.request(request)


## A killing blow: resolve the victim's death once from their kit, start it,
## and time the dead hand's release from that same style — so the collapse and
## the release can never belong to different deaths.
func _present_death(request: DeathPresentationRequest) -> void:
	request.spec = _kits.combatant(request.slot).fighter.death_spec(request.cause, request.key)
	if _deaths.present(request):
		_drops.request(WeaponDropRequest.from_blade(request.slot, request.spec.weapon_release_time, _current.fighter(request.slot), request.key))


## The hands let go: the held look is hidden and a presentation body carries a
## fresh look built from the same kits, starting where the sword was drawn
## (the carriage) with the blade's spin plus the presented body's own motion.
## Physics bodies need an unscaled transform, and a collapse squashes the
## body, so the carriage's basis is orthonormalized.
func _launch_drop(drop: WeaponDropRequest) -> void:
	var proxy := _fighters[drop.slot]
	var row := _current.fighter(drop.slot)
	var at := proxy.sword_carriage().global_transform
	var length := row.tip_radius - row.blade_base_radius
	var look := CombatantVisuals.weapon_look(proxy.combatant_kit(), proxy.side, row.blade_base_radius, row.tip_radius)
	var body := DroppedWeapon3D.create(look, row.weapon_mass, length, _kits.weapon.blade_width, row.blade_base_radius + length * 0.5)
	proxy.detach_weapon()
	add_child(body)
	body.launch(Transform3D(at.basis.orthonormalized(), at.origin), drop.linear_velocity + proxy.root_velocity(), drop.angular_velocity)
	_dropped.append(body)


## Terminal latches, for tests and debug: whether this round's death for
## `slot` has started, and whether its sword is waiting to drop or has dropped.
func has_death_started(slot: int) -> bool:
	return _deaths.has_started(slot)


func is_drop_pending(slot: int) -> bool:
	return _drops.is_pending(slot)


func has_drop_released(slot: int) -> bool:
	return _drops.has_released(slot)


func dropped_weapons() -> Array[DroppedWeapon3D]:
	var live: Array[DroppedWeapon3D] = []
	for body in _dropped:
		if is_instance_valid(body):
			live.append(body)
	return live


func _clear_drops() -> void:
	_drops.reset()
	for body in _dropped:
		if is_instance_valid(body):
			body.queue_free()
	_dropped.clear()


func _play(request: AudioCueRequest) -> void:
	var kit := _kits.arena if request.kit_source == AudioCueRequest.KitSource.ARENA else _kits.weapon
	if request.flat:
		## A kit without a dedicated round-win sting uses its round sting.
		if not _audio.play_flat(request.cue, kit, request.volume_db, request.key) and request.cue == PresentationKit.CUE_ROUND_WIN:
			_audio.play_flat(PresentationKit.CUE_ROUND, kit, request.volume_db, request.key)
	elif not _audio.play(request.cue, kit, request.world_position, request.volume_db, request.pitch, request.key) and request.cue == PresentationKit.CUE_WHIFF:
		## A kit without its own whiff take plays the swing take at the
		## whiff's hollow pitch.
		_audio.play(PresentationKit.CUE_SWING, kit, request.world_position, request.volume_db, request.pitch, request.key)


func _draw(request: VfxRequest) -> void:
	match request.kind:
		VfxRequest.Kind.SPARKS:
			_vfx.sparks(request.world_position, request.direction, request.color, request.count, request.speed, request.flash_scale)
		VfxRequest.Kind.RING:
			_vfx.ring(request.world_position, request.color, request.size, request.flash_scale)
		VfxRequest.Kind.STREAK:
			_vfx.streak(request.world_position, request.direction, request.color, request.flash_scale)
		VfxRequest.Kind.DUST:
			_vfx.dust(request.world_position, request.direction, request.color, request.count, request.speed, request.flash_scale)
		VfxRequest.Kind.AXIAL:
			_vfx.axial(request.world_position, request.direction, request.color, request.count, request.speed, request.size, request.flash_scale)
		VfxRequest.Kind.FLASH:
			_vfx.lethal_flash(request.world_position, request.direction, request.color, request.size, request.count, request.flash_scale)


func _fighter_cue(request: FighterCueRequest) -> void:
	match request.kind:
		FighterCueRequest.Kind.HIT_FLASH:
			if request.slot >= 0:
				_fighters[request.slot].flash_hit(request.intensity)
		FighterCueRequest.Kind.CRITICAL_FLASH:
			if request.slot >= 0:
				_fighters[request.slot].flash_hit(request.intensity, true)
		FighterCueRequest.Kind.HAPTIC_BLADE:
			_haptics.pulse(Haptics.BLADE)
		FighterCueRequest.Kind.HAPTIC_BODY:
			_haptics.pulse(Haptics.BODY)
		FighterCueRequest.Kind.HAPTIC_CRITICAL:
			_haptics.pulse(Haptics.CRITICAL)


func _impulse(strength: float, direction: Vector3 = Vector3.ZERO) -> void:
	if _camera != null:
		_camera.impulse(strength, _options, direction)
