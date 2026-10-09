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

## While blades are bound, a couple of grind sparks every few ticks at the
## point where they met.
const GRIND_EVERY_TICKS := 4
const GRIND_SPARKS := 2
const GRIND_SPEED := 0.9

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
var _bind_point := Vector3.ZERO
var _last_frame: FeedbackFrame = FeedbackFrame.new()
## Killing blows → the first backend that can carry them out. Primitive today;
## a ragdoll backend goes ahead of it once the rig has a physical skeleton.
var _deaths: DeathPresentationController
## Swords waiting for the hands to let go, and the ones already tumbling.
var _drops := WeaponDropController.new()
var _dropped: Array[DroppedWeapon3D] = []


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
	_audio.play_music(_kits.arena)


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
		_deaths.reset()
		_clear_drops()
	var style := _kits.match_loadout.vfx_style if _kits.match_loadout != null else null
	_last_frame = CombatFeedbackDirector.process(snapshot, events, _kits.weapon, _options.flash_scale(), _options.particle_intensity, style)
	_apply(_last_frame)
	_grind(snapshot, style)


func render(alpha: float, delta: float) -> void:
	if _current == null or _disposed:
		return
	var weight := clampf(alpha, 0.0, 1.0)
	var first := _pose(0, weight, delta)
	var second := _pose(1, weight, delta)
	_vectors.update(_current)
	_vfx.advance(delta)
	for drop in _drops.advance(delta):
		_launch_drop(drop)
	if _camera != null:
		_camera.frame(first, second, delta, _options, _snap)
	_snap = false


func fighter_proxy(slot: int) -> FighterPresentation3D:
	return _fighters[slot]


## The once-per-set introduction, built over this presenter's world. The
## screen decides whether a set is starting; the presenter only stages it.
func create_intro(gameplay_camera: Camera3D) -> SetIntroDirector:
	var proxies: Array[Node3D] = []
	for proxy in _fighters:
		proxies.append(proxy)
	for ribbon in _trails:
		proxies.append(ribbon)
	var intro := SetIntroDirector.create(_kits, _current, _audio, proxies, gameplay_camera)
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


func audio() -> AudioDirector:
	return _audio


func haptics() -> Haptics:
	return _haptics


func current_snapshot() -> PresentationSnapshot:
	return _current


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
		var proxy := FighterPresentation3D.create(slot, row.side, _kits.combatant(slot), row.body_radius, row.hilt_radius, row.tip_radius)
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
	_vfx = VfxDirector.new()
	add_child(_vfx)
	_audio = AudioDirector.new()
	add_child(_audio)
	var backends: Array[DeathPresentationBackend] = [PrimitiveDeathBackend.new(_fighters)]
	_deaths = DeathPresentationController.new(backends)
	_previous = first
	_current = first


## Interpolate one fighter between the last two snapshots, pose its proxy
## and trail, and return where it stands in the world.
func _pose(slot: int, weight: float, delta: float) -> Vector3:
	var from := _previous.fighter(slot)
	var to := _current.fighter(slot)
	var world := ArenaTransform.to_world(lerpf(from.x, to.x, weight), lerpf(from.y, to.y, weight))
	var proxy := _fighters[slot]
	proxy.apply_pose(world, lerp_angle(from.facing, to.facing, weight), lerpf(from.weapon_angle, to.weapon_angle, weight), to, delta)
	var blade := proxy.blade_points()
	_trails[slot].add_sample(blade[0], blade[1], to.swing_potential, to.blade_speed, _kits.weapon.trail_min_speed)
	_trails[slot].advance(delta)
	_tension(slot, to, world)
	return world


## The wind-back needs no invented cue: the blade physically travels backwards,
## which is already the best anticipation the game has. Audio only tightens
## behind it, rising with the wind-back actually earned and plateauing when
## there is no more to earn. No charge glow (UX §19).
func _tension(slot: int, row: PresentationFighter, world: Vector3) -> void:
	if row.phase == CombatPhase.Id.CHARGING and row.is_alive():
		_audio.hold_tension(slot, _kits.weapon, world, row.charge)
	else:
		_audio.release_tension(slot)


## A bind lasts as long as the snapshot says the blades are pinned, so its
## grind is held from the snapshot rather than timed from the event.
func _grind(snapshot: PresentationSnapshot, style: VfxStyleKit) -> void:
	var bound := snapshot.fighter(0).phase == CombatPhase.Id.BIND or snapshot.fighter(1).phase == CombatPhase.Id.BIND
	if not bound:
		_audio.release_bind(0)
		return
	if _options.particle_intensity > 0.0 and snapshot.tick % GRIND_EVERY_TICKS == 0:
		var color := style.grind if style != null else RiposteTheme.SPARK
		_vfx.sparks(_bind_point, Vector3.UP, color, GRIND_SPARKS, GRIND_SPEED, _options.flash_scale())


func _apply(frame: FeedbackFrame) -> void:
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
		_deaths.present(request)
	for request in frame.fall_requests:
		_fighters[request.slot].begin_fall(request)
	for request in frame.weapon_drop_requests:
		_drops.request(request)


## The hands let go: the held look is hidden and a presentation body carries a
## copy of it, starting from the pivot with the blade's spin plus the presented
## body's own motion. Physics bodies need an unscaled transform, and a collapse
## squashes the body, so the pivot's basis is orthonormalized.
func _launch_drop(drop: WeaponDropRequest) -> void:
	var proxy := _fighters[drop.slot]
	var row := _current.fighter(drop.slot)
	var at := proxy.sword_pivot().global_transform
	var length := row.tip_radius - row.hilt_radius
	var body := DroppedWeapon3D.create(proxy.detach_weapon(), drop.linear_velocity + proxy.root_velocity(), drop.angular_velocity, length, _kits.weapon.blade_width, row.hilt_radius + length * 0.5)
	add_child(body)
	body.global_transform = Transform3D(at.basis.orthonormalized(), at.origin)
	_dropped.append(body)


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
	if request.hold:
		_bind_point = request.world_position
		_audio.hold_bind(0, kit, request.world_position, 1.0, request.key)
	elif request.flat:
		## A kit without a dedicated round-win sting uses its round sting.
		if not _audio.play_flat(request.cue, kit, request.volume_db, request.key) and request.cue == PresentationKit.CUE_ROUND_WIN:
			_audio.play_flat(PresentationKit.CUE_ROUND, kit, request.volume_db, request.key)
	else:
		_audio.play(request.cue, kit, request.world_position, request.volume_db, request.pitch, request.key)


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
