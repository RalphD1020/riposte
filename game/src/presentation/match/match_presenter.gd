class_name MatchPresenter
extends Node3D

## The transient 3D root and the one presentation coordinator for a match.
##
## Per simulation tick: `push(snapshot, events)` stores the new snapshot and
## turns events into feedback (sparks, rings, sounds, hitstop, impulses,
## haptics) using the cues and feel values declared by the kits. Per frame:
## `render(alpha, delta)` interpolates between the last two snapshots with
## the tick driver's alpha and poses the passive proxies. It never steps,
## reads, or mutates the simulation; hitstop is a request to the clock owner.
## Generic code here never names a content identity.
##
## Implements: /spec/invariants.md#pres-001
## See also: /docs/concepts/presentation.md

signal hitstop_requested(seconds: float)

## Body-hit tiers by damage (UX §21): light < heavy < devastating.
const DAMAGE_HEAVY := 15.0
const DAMAGE_DEVASTATING := 55.0
const CRITICAL_EXTRA_HITSTOP := 0.02
## Camera impulse strength per impact tier (Reduced Motion disables all).
const IMPULSE_STRONG_BLADE := 0.08
const IMPULSE_HEAVY_BODY := 0.072
const IMPULSE_DEVASTATING_BODY := 0.12
const IMPULSE_CRITICAL := 0.2
## Sparks per blade contact class: count and launch speed (m/s).
const SPARK_COUNT_LIGHT := 4
const SPARK_COUNT_SOLID := 8
const SPARK_COUNT_STRONG := 12
const SPARK_SPEED_LIGHT := 2.0
const SPARK_SPEED_SOLID := 3.2
const SPARK_SPEED_STRONG := 4.5
## Impact rings: parry size, and body rings that grow with damage.
const PARRY_RING_SIZE := 0.8
const BODY_RING_SIZE := 0.6
const BODY_RING_SIZE_PER_DAMAGE := 0.01
const BODY_RING_HEIGHT := 0.05
## Mix (dB) and pitch: the swing whoosh deepens and swells with charge.
const SWING_VOLUME_DB_TAP := -6.0
const SWING_VOLUME_DB_FULL := 0.0
const SWING_PITCH_TAP := 1.15
const SWING_PITCH_FULL := 0.9
const CHARGE_VOLUME_DB := -10.0
const ROUND_VOLUME_DB := -4.0
const DEVASTATING_VOLUME_DB := 2.0

var _kits: DuelKits
var _options: PresentationOptions
var _camera: DuelCameraRig
var _haptics := Haptics.new()
var _arena: ArenaScaffold
var _fighters: Array[FighterPresentation3D] = []
var _trails: Array[SwordTrail3D] = []
var _vfx: VfxDirector
var _audio: AudioDirector
var _previous: PresentationSnapshot
var _current: PresentationSnapshot
var _snap: bool = true
var _disposed: bool = false


static func create(kits: DuelKits, options: PresentationOptions, camera: DuelCameraRig, arena_radius: float, first: PresentationSnapshot) -> MatchPresenter:
	var presenter := MatchPresenter.new()
	presenter.name = "MatchPresentation"
	presenter._kits = kits
	presenter._options = options
	presenter._camera = camera
	presenter._haptics.enabled = options.haptics
	presenter._build(arena_radius, first)
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
	for event in events:
		_dispatch(event)


func render(alpha: float, delta: float) -> void:
	if _current == null or _disposed:
		return
	var weight := clampf(alpha, 0.0, 1.0)
	var first := _pose(0, weight, delta)
	var second := _pose(1, weight, delta)
	_vfx.advance(delta)
	if _camera != null:
		_camera.frame(first, second, delta, _options, _snap)
	_snap = false


func fighter_proxy(slot: int) -> FighterPresentation3D:
	return _fighters[slot]


func trail(slot: int) -> SwordTrail3D:
	return _trails[slot]


func vfx() -> VfxDirector:
	return _vfx


func audio() -> AudioDirector:
	return _audio


func haptics() -> Haptics:
	return _haptics


func current_snapshot() -> PresentationSnapshot:
	return _current


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


func _build(arena_radius: float, first: PresentationSnapshot) -> void:
	_arena = ArenaScaffold.create(_kits.arena, arena_radius)
	add_child(_arena)
	for slot in 2:
		var row := first.fighter(slot)
		var proxy := FighterPresentation3D.create(slot, _kits.fighter, _kits.weapon, row.body_radius, row.hilt_radius, row.tip_radius)
		proxy.set_charge_indicator(_options.show_charge_indicator)
		proxy.set_high_contrast(_options.high_contrast_weapons)
		add_child(proxy)
		_fighters.append(proxy)
		var capacity := _kits.weapon.trail_samples * (2 if _options.high_contrast_weapons else 1)
		var ribbon := SwordTrail3D.create(proxy.blade_color(), capacity)
		add_child(ribbon)
		_trails.append(ribbon)
	_vfx = VfxDirector.new()
	add_child(_vfx)
	_audio = AudioDirector.new()
	add_child(_audio)
	_previous = first
	_current = first


## Interpolate one fighter between the last two snapshots, pose its proxy
## and trail, and return where it stands in the world.
func _pose(slot: int, weight: float, delta: float) -> Vector3:
	var from := _previous.fighter(slot)
	var to := _current.fighter(slot)
	var world := ArenaTransform.to_world(lerpf(from.x, to.x, weight), lerpf(from.y, to.y, weight))
	var proxy := _fighters[slot]
	proxy.apply_pose(world, lerp_angle(from.facing, to.facing, weight), lerpf(from.weapon_angle, to.weapon_angle, weight), to.charge, to.phase, to.is_alive(), delta)
	var blade := proxy.blade_points()
	_trails[slot].add_sample(blade[0], blade[1], to.blade_speed, _kits.weapon.trail_min_speed)
	_trails[slot].advance(delta)
	return world


func _fighter_world(slot: int, height: float = 0.0) -> Vector3:
	var fighter := _current.fighter(slot)
	return ArenaTransform.to_world(fighter.x, fighter.y, height)


func _contact_world(event: DuelEvent) -> Vector3:
	return ArenaTransform.to_world(event.number(DuelEventKeys.X), event.number(DuelEventKeys.Y), _kits.weapon.blade_height)


func _dispatch(event: DuelEvent) -> void:
	var weapon := _kits.weapon
	var flash := _options.flash_scale()
	match event.type:
		DuelEventTypes.ATTACK_RELEASED:
			var charge := event.number(DuelEventKeys.CHARGE)
			_audio.play(PresentationKit.CUE_SWING, weapon, _fighter_world(event.actor), lerpf(SWING_VOLUME_DB_TAP, SWING_VOLUME_DB_FULL, charge), lerpf(SWING_PITCH_TAP, SWING_PITCH_FULL, charge))
		DuelEventTypes.CHARGE_STARTED:
			_audio.play(PresentationKit.CUE_CHARGE, weapon, _fighter_world(event.actor), CHARGE_VOLUME_DB)
		DuelEventTypes.BLADE_CONTACT:
			_on_blade_contact(event, weapon, flash)
		DuelEventTypes.PARRY:
			_vfx.ring(_contact_world(event), RiposteTheme.SPARK, PARRY_RING_SIZE, flash)
		DuelEventTypes.BODY_HIT:
			_on_body_hit(event, weapon, flash)
		DuelEventTypes.CRITICAL_HIT:
			_vfx.streak(_fighter_world(event.actor, weapon.blade_height), _fighter_world(event.target, weapon.blade_height), RiposteTheme.CRITICAL, flash)
			_audio.play(PresentationKit.CUE_CRITICAL, weapon, _fighter_world(event.target))
			hitstop_requested.emit(weapon.hitstop_devastating + CRITICAL_EXTRA_HITSTOP)
			_haptics.pulse(Haptics.CRITICAL)
			_impulse(IMPULSE_CRITICAL)
		DuelEventTypes.ROUND_STARTED, DuelEventTypes.ROUND_ENDED:
			_audio.play_flat(PresentationKit.CUE_ROUND, _kits.arena, ROUND_VOLUME_DB)


func _on_blade_contact(event: DuelEvent, weapon: PresentationKit, flash: float) -> void:
	var world := _contact_world(event)
	var a := _current.fighter(0)
	var b := _current.fighter(1)
	var normal := Vector3(b.x - a.x, 0.0, -(b.y - a.y)).normalized().rotated(Vector3.UP, PI * 0.5)
	match StringName(event.text(DuelEventKeys.CONTACT_CLASS)):
		ContactResolver.CLASS_STRONG:
			_vfx.sparks(world, normal, RiposteTheme.SPARK, SPARK_COUNT_STRONG, SPARK_SPEED_STRONG, flash)
			_audio.play(PresentationKit.CUE_BLADE_STRONG, weapon, world)
			hitstop_requested.emit(weapon.hitstop_blade_strong)
			_impulse(IMPULSE_STRONG_BLADE)
		ContactResolver.CLASS_SOLID:
			_vfx.sparks(world, normal, RiposteTheme.SPARK, SPARK_COUNT_SOLID, SPARK_SPEED_SOLID, flash)
			_audio.play(PresentationKit.CUE_BLADE_SOLID, weapon, world)
			hitstop_requested.emit(weapon.hitstop_blade_solid)
		_:
			_vfx.sparks(world, normal, RiposteTheme.SPARK, SPARK_COUNT_LIGHT, SPARK_SPEED_LIGHT, flash)
			_audio.play(PresentationKit.CUE_BLADE_LIGHT, weapon, world)
			hitstop_requested.emit(weapon.hitstop_blade_light)
	_haptics.pulse(Haptics.BLADE)


func _on_body_hit(event: DuelEvent, weapon: PresentationKit, flash: float) -> void:
	var damage := event.number(DuelEventKeys.DAMAGE)
	var world := _contact_world(event)
	_fighters[event.target].flash_hit(flash)
	_vfx.ring(_fighter_world(event.target, BODY_RING_HEIGHT), RiposteTheme.BODY_IMPACT, BODY_RING_SIZE + damage * BODY_RING_SIZE_PER_DAMAGE, flash)
	if damage >= DAMAGE_DEVASTATING:
		_audio.play(PresentationKit.CUE_BODY_HEAVY, weapon, world, DEVASTATING_VOLUME_DB)
		hitstop_requested.emit(weapon.hitstop_devastating)
		_impulse(IMPULSE_DEVASTATING_BODY)
	elif damage >= DAMAGE_HEAVY:
		_audio.play(PresentationKit.CUE_BODY_HEAVY, weapon, world)
		hitstop_requested.emit(weapon.hitstop_body_heavy)
		_impulse(IMPULSE_HEAVY_BODY)
	else:
		_audio.play(PresentationKit.CUE_BODY_LIGHT, weapon, world)
		hitstop_requested.emit(weapon.hitstop_body_light)
	_haptics.pulse(Haptics.BODY)


func _impulse(strength: float) -> void:
	if _camera != null:
		_camera.impulse(strength, _options)
